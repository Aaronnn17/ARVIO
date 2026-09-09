import { buildSportsGuideEvents } from "@/lib/sportsGuide";
import type { IptvChannel, IptvNowNext } from "@/lib/types";

self.onmessage = (message: MessageEvent<{ channels: IptvChannel[]; guide: Record<string, IptvNowNext>; now: number }>) => {
  const { channels, guide, now } = message.data;
  self.postMessage(buildSportsGuideEvents(channels, guide, now));
};
