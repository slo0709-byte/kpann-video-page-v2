import Service from "@ember/service";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";

// 观看页当前播放的是合集中的第几个。
// 播放器与合集列表是两个独立的 outlet，靠这个 service 共享「当前是哪一个」；
// 渲染期只读 indexFor(topicId)，不在渲染中改状态。
export default class KpvPlayer extends Service {
  @tracked selection = { topicId: null, index: 0 };

  // 当前这个视频帖的模型：播放器渲染时登记，动作排里的「沉浸」按钮读它
  @tracked topic = null;

  @action
  setTopic(topic) {
    if (this.topic !== topic) {
      this.topic = topic;
    }
  }

  indexFor(topicId) {
    return this.selection.topicId === topicId ? this.selection.index : 0;
  }

  @action
  select(topicId, index) {
    if (this.selection.topicId === topicId && this.selection.index === index) {
      return;
    }
    this.selection = { topicId, index };
  }
}
