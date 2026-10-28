// ARVIO's independent, software-only keyframe worker. FFmpeg is dynamically linked.
#include <jni.h>
#include <android/bitmap.h>
#include <atomic>
#include <chrono>
#include <string>
#include <algorithm>
#include <array>
#include <cmath>
#include <sys/resource.h>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/mem.h>
}

namespace {
std::atomic<int64_t> requested{0};
struct Session {
    AVFormatContext* format = nullptr;
    AVCodecContext* codec = nullptr;
    SwsContext* scaler = nullptr;
    std::string url;
    int stream = -1;
    int64_t request = 0;
    int64_t deadline = 0;
    int64_t origin = 0;
    ~Session() { reset(); }
    void reset() {
        sws_freeContext(scaler); scaler = nullptr;
        avcodec_free_context(&codec);
        avformat_close_input(&format);
        stream = -1; url.clear(); origin = 0;
    }
};
// Only the service's single worker thread owns this context.
Session session;
int64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
int interrupted(void* opaque) {
    auto* s = static_cast<Session*>(opaque);
    return requested.load() != s->request || nowMs() >= s->deadline;
}

// Tone-map only the small output, not full-resolution video. PQ/HLG screenshots
// otherwise look almost black. BT.2020 linear RGB is converted to the UI's gamut.
void toneMap(uint8_t* pixels, int width, int height, int stride, AVColorTransferCharacteristic transfer) {
    if (transfer != AVCOL_TRC_SMPTE2084 && transfer != AVCOL_TRC_ARIB_STD_B67) return;
    std::array<float, 256> linear{};
    for (int i = 0; i < 256; ++i) {
        float x = i / 255.f;
        if (transfer == AVCOL_TRC_SMPTE2084) {
            float p = std::pow(x, 1.f / 78.84375f);
            linear[i] = 10000.f / 203.f * std::pow(std::max(p - .8359375f, 0.f) /
                std::max(18.8515625f - 18.6875f * p, .000001f), 1.f / .1593017578125f);
        } else {
            float scene = x <= .5f ? x * x / 3.f : (std::exp((x - .55991073f) / .17883277f) + .28466892f) / 12.f;
            linear[i] = 1000.f / 203.f * std::pow(scene, 1.2f);
        }
    }
    static const auto srgb = [] {
        std::array<uint8_t, 4096> result{};
        for (int i = 0; i < 4096; ++i) {
            float x = i / 4095.f;
            result[i] = uint8_t(std::lround(255.f * (x <= .0031308f ? 12.92f * x : 1.055f * std::pow(x, 1.f / 2.4f) - .055f)));
        }
        return result;
    }();
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        auto* p = pixels + y * stride + x * 4;
        float r = linear[p[0]], g = linear[p[1]], b = linear[p[2]];
        float red = std::max(0.f, 1.6605f*r - .5876f*g - .0728f*b);
        float green = std::max(0.f, -.1246f*r + 1.1329f*g - .0083f*b);
        float blue = std::max(0.f, -.0182f*r - .1006f*g + 1.1187f*b);
        float luminance = .2126f*red + .7152f*green + .0722f*blue;
        float scale = (1.f + luminance / 24.266f) / (1.f + luminance);
        p[0] = srgb[int(std::clamp(red*scale, 0.f, 1.f) * 4095)];
        p[1] = srgb[int(std::clamp(green*scale, 0.f, 1.f) * 4095)];
        p[2] = srgb[int(std::clamp(blue*scale, 0.f, 1.f) * 4095)];
    }
}
bool openSource(const std::string& url) {
    if (session.format && session.url == url) return true;
    session.reset();
    session.format = avformat_alloc_context();
    if (!session.format) return false;
    session.format->interrupt_callback = {interrupted, &session};
    AVDictionary* options = nullptr;
    // Credentials and remote network access stay in ARVIO's bounded range proxy.
    av_dict_set(&options, "protocol_whitelist", "http,tcp", 0);
    av_dict_set(&options, "rw_timeout", "2500000", 0);
    av_dict_set(&options, "probesize", "1048576", 0);
    av_dict_set(&options, "analyzeduration", "1000000", 0);
    int result = avformat_open_input(&session.format, url.c_str(), nullptr, &options);
    av_dict_free(&options);
    if (result < 0) return false;
    // MP4/MKV usually describe the codec completely in their headers. Avoid
    // reading/decoding the opening seconds of a 4K remux just to rediscover it.
    session.stream = av_find_best_stream(session.format, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    auto* initial = session.stream >= 0 ? session.format->streams[session.stream]->codecpar : nullptr;
    if (!initial || initial->width <= 0 || initial->height <= 0 ||
        (initial->codec_id != AV_CODEC_ID_VP9 && initial->extradata_size <= 0)) {
        if (avformat_find_stream_info(session.format, nullptr) < 0) return false;
        session.stream = av_find_best_stream(session.format, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    }
    if (session.stream < 0) return false;
    auto* stream = session.format->streams[session.stream];
    auto* parameters = stream->codecpar;
    for (int i = 0; i < parameters->nb_coded_side_data; ++i) {
        const auto& side = parameters->coded_side_data[i];
        if (side.type == AV_PKT_DATA_DOVI_CONF && side.size >= sizeof(AVDOVIDecoderConfigurationRecord) &&
            reinterpret_cast<const AVDOVIDecoderConfigurationRecord*>(side.data)->dv_profile == 5)
            return false; // Profile 5 has no HDR10-compatible base; never display a green/purple frame.
    }
    if (parameters->width <= 0 || parameters->height <= 0 ||
        int64_t(parameters->width) * parameters->height > 3840LL * 2160LL) return false;
    const AVCodec* codec = avcodec_find_decoder(parameters->codec_id);
    if (!codec) return false;
    session.codec = avcodec_alloc_context3(codec);
    if (!session.codec || avcodec_parameters_to_context(session.codec, parameters) < 0) return false;
    session.codec->thread_count = 1;
    session.codec->max_pixels = 3840LL * 2160LL;
    session.codec->thread_type = 0;
    session.codec->skip_frame = AVDISCARD_NONKEY;
    if (avcodec_open2(session.codec, codec, nullptr) < 0) return false;
    for (unsigned i = 0; i < session.format->nb_streams; ++i)
        if (int(i) != session.stream) session.format->streams[i]->discard = AVDISCARD_ALL;
    session.origin = stream->start_time == AV_NOPTS_VALUE ? 0 : stream->start_time;
    session.url = url;
    return true;
}
}

extern "C" JNIEXPORT void JNICALL
Java_com_arflix_tv_ui_screens_player_preview_KeyframeNative_interrupt(JNIEnv*, jobject, jlong id) {
    requested.store(id);
}

extern "C" JNIEXPORT void JNICALL
Java_com_arflix_tv_ui_screens_player_preview_KeyframeNative_close(JNIEnv*, jobject) {
    session.reset();
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_arflix_tv_ui_screens_player_preview_KeyframeNative_frame(
    JNIEnv* env, jobject, jstring address, jlong position, jlong id) {
    setpriority(PRIO_PROCESS, 0, 19);
    av_max_alloc(32 * 1024 * 1024);
    av_log_set_level(AV_LOG_QUIET); // FFmpeg errors can include signed resource addresses.
    const char* chars = env->GetStringUTFChars(address, nullptr);
    if (!chars) return nullptr;
    std::string url(chars);
    env->ReleaseStringUTFChars(address, chars);
    if (url.rfind("http://127.0.0.1:", 0) != 0 || position < 0) return nullptr;
    session.request = id;
    session.deadline = nowMs() + 8000;
    if (interrupted(&session)) return nullptr;
    if (!openSource(url)) { session.reset(); return nullptr; }
    auto* stream = session.format->streams[session.stream];
    int64_t target = av_rescale_q(position, AVRational{1, 1000}, stream->time_base) + session.origin;
    // Start at the preceding independently decodable frame; never decode a full GOP.
    if (av_seek_frame(session.format, session.stream, target, AVSEEK_FLAG_BACKWARD) < 0) {
        session.reset(); return nullptr;
    }
    avcodec_flush_buffers(session.codec);
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    jobject output = nullptr;
    if (!packet || !frame) { av_packet_free(&packet); av_frame_free(&frame); return nullptr; }
    for (int packets = 0; packets < 4096 && !interrupted(&session); ++packets) {
        if (av_read_frame(session.format, packet) < 0) break;
        if (packet->stream_index != session.stream || !(packet->flags & AV_PKT_FLAG_KEY)) {
            av_packet_unref(packet); continue;
        }
        int sent = avcodec_send_packet(session.codec, packet);
        av_packet_unref(packet);
        if (sent < 0) break;
        int received = avcodec_receive_frame(session.codec, frame);
        if (received == AVERROR(EAGAIN)) {
            // Delayed codecs may retain the sole keyframe until drain.
            avcodec_send_packet(session.codec, nullptr);
            received = avcodec_receive_frame(session.codec, frame);
        }
        if (received < 0 || frame->best_effort_timestamp == AV_NOPTS_VALUE ||
            frame->width <= 0 || frame->height <= 0 ||
            int64_t(frame->width) * frame->height > 3840LL * 2160LL) break;
        int64_t actual = av_rescale_q(frame->best_effort_timestamp - session.origin,
                                     stream->time_base, AVRational{1, 1000});
        if (actual < 0 || llabs(actual - position) > 5000 || interrupted(&session)) break;
        const int width = 320;
        int height = std::clamp(int(int64_t(width) * frame->height / frame->width), 1, 320);
        jclass bitmapClass = env->FindClass("android/graphics/Bitmap");
        jclass configClass = env->FindClass("android/graphics/Bitmap$Config");
        jobject config = env->GetStaticObjectField(configClass,
            env->GetStaticFieldID(configClass, "ARGB_8888", "Landroid/graphics/Bitmap$Config;"));
        jobject bitmap = env->CallStaticObjectMethod(bitmapClass, env->GetStaticMethodID(bitmapClass,
            "createBitmap", "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;"), width, height, config);
        if (!bitmap || env->ExceptionCheck()) break;
        AndroidBitmapInfo info{};
        void* pixels = nullptr;
        if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS ||
            AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS) break;
        session.scaler = sws_getCachedContext(session.scaler, frame->width, frame->height,
            static_cast<AVPixelFormat>(frame->format), width, height, AV_PIX_FMT_RGBA,
            SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
        if (session.scaler) {
            const int* coefficients = sws_getCoefficients(frame->colorspace == AVCOL_SPC_BT2020_NCL ? SWS_CS_BT2020 : SWS_CS_ITU709);
            sws_setColorspaceDetails(session.scaler, coefficients, frame->color_range == AVCOL_RANGE_JPEG,
                sws_getCoefficients(SWS_CS_ITU709), 1, 0, 1 << 16, 1 << 16);
        }
        uint8_t* destination[] = {static_cast<uint8_t*>(pixels), nullptr, nullptr, nullptr};
        int strides[] = {int(info.stride), 0, 0, 0};
        int scaled = session.scaler ? sws_scale(session.scaler, frame->data, frame->linesize,
            0, frame->height, destination, strides) : 0;
        if (scaled == height) toneMap(static_cast<uint8_t*>(pixels), width, height, info.stride, frame->color_trc);
        AndroidBitmap_unlockPixels(env, bitmap);
        if (scaled == height && !interrupted(&session)) {
            jclass resultClass = env->FindClass("com/arflix/tv/ui/screens/player/preview/KeyframeResult");
            output = env->NewObject(resultClass, env->GetMethodID(resultClass, "<init>",
                "(Landroid/graphics/Bitmap;J)V"), bitmap, actual);
        }
        break;
    }
    av_packet_free(&packet);
    av_frame_free(&frame);
    if (!output) session.reset(); // Interrupted AVIO must not poison the next request.
    return output;
}
