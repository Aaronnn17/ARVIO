package com.arflix.tv.network

import okhttp3.Call
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody
import okio.ForwardingSource
import okio.buffer
import java.util.concurrent.ConcurrentHashMap

/** Track streaming bodies, which may outlive their OkHttp dispatcher entries. */
internal class IptvPlaybackConnections : Interceptor {
    private val calls = ConcurrentHashMap.newKeySet<Call>()

    fun cancelAll() {
        calls.toList().forEach { it.cancel() }
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val call = chain.call()
        calls.add(call)
        try {
            val response = chain.proceed(chain.request())
            val body = response.body ?: run {
                calls.remove(call)
                return response
            }
            val source = object : ForwardingSource(body.source()) {
                override fun close() {
                    try { super.close() } finally { calls.remove(call) }
                }
            }.buffer()
            return response.newBuilder().body(object : ResponseBody() {
                override fun contentType() = body.contentType()
                override fun contentLength() = body.contentLength()
                override fun source() = source
            }).build()
        } catch (error: Throwable) {
            calls.remove(call)
            throw error
        }
    }
}
