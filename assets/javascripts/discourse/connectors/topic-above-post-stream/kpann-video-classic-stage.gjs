import Component from "@glimmer/component";
import KpannVideoStage from "discourse/plugins/kpann-video-page/discourse/connectors/kpann-video-stage/kpann-video-stage";
import KpannVideoCollection from "discourse/plugins/kpann-video-page/discourse/connectors/kpann-video-collection/kpann-video-collection";

// 经典（平铺楼层）话题页：把播放器放进官方 outlet `topic-above-post-stream`，
// 它的位置就在 <TopicTitle> 之前，所以播放器自然排在标题上面。
// 不复制核心模板，升级不用管。
export default class KpannVideoClassicStage extends Component {
  get topic() {
    return this.args.outletArgs?.model || this.args.model;
  }

  get isVideoTopic() {
    // 嵌套视图自己有 outlet，这套只在经典（平铺）页生效，否则会渲染两份
    if (this.topic?.is_nested_view) {
      return false;
    }
    const list = this.topic?.kpann_videos;
    return (Array.isArray(list) && list.length > 0) || !!this.topic?.kpann_embed_url;
  }

  <template>
    {{#if this.isVideoTopic}}
      <div class="kpv-classic">
        <KpannVideoStage @model={{this.topic}} />
        <KpannVideoCollection @model={{this.topic}} />
      </div>
    {{/if}}
  </template>
}




