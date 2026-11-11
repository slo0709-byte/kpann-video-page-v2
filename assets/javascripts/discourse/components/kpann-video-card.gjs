import Component from "@glimmer/component";
import dFormatDate from "discourse/ui-kit/helpers/d-format-date";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { classesForUser } from "discourse/ui-kit/helpers/d-avatar";

// 视频分类列表里的一个格子（桌面和手机共用）。
// 版式照 YouTube 主页的三列网格：缩略图在上（16:9、直角），下面一行是
// 「头像 + 文字列」，文字列第一块是标题（最多两行），第二块是元信息单行。
// 外观零装饰：没有边框、圆角、阴影、hover 抬升——只要布局。
//
// 结构约束（重要）：整张卡是一个 <a>，里面不能再放 <a>。
// HTML 不允许链接嵌套，浏览器会把内层 <a> 拆散成匿名节点，
// 留下的 [data-user-card] 会被核心当成「点头像弹用户资料卡」的触发器，
// 结果点卡片任意位置都可能弹出资料卡。所以头像用 <span> 包，
// 用 dAvatar 自己出图；名牌靠 data-user-card 挂在纯文字上生效。
export default class KpannVideoCard extends Component {
  get topic() {
    return this.args.topic || this.args.outletArgs?.topic;
  }

  get cover() {
    return this.topic?.kpann_cover_url || null;
  }

  get creator() {
    return this.topic?.creator || null;
  }

  get username() {
    return this.topic?.creator?.username || this.topic?.kpann_poster_username || null;
  }

  get likes() {
    return this.topic?.like_count || 0;
  }

  get replies() {
    return Math.max((this.topic?.posts_count || 1) - 1, 0);
  }

  get views() {
    return this.topic?.views || 0;
  }

  // 时长角标：只有抓到时长才显示
  get duration() {
    const raw = this.topic?.kpann_duration || this.topic?.kpann_videos?.[0]?.duration;
    const seconds = Number(raw);
    if (!seconds || seconds <= 0) {
      return null;
    }
    const pad = (n) => String(n).padStart(2, "0");
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
  }

  // 头像框/名牌这些装扮类由原生 classesForUser 提供，跟核心列表行一致
  get creatorClasses() {
    return this.creator ? classesForUser(this.creator).join(" ") : "";
  }

  <template>
    <td class="kpv-card-cell">
      <a class="kpv-card" href={{this.topic.url}}>
        <span class="kpv-card__thumb {{unless this.cover 'is-empty'}}">
          {{#if this.cover}}
            <img src={{this.cover}} alt="" loading="lazy">
          {{else}}
            {{dIcon "play"}}
          {{/if}}
          {{#if this.duration}}
            <span class="kpv-card__duration">{{this.duration}}</span>
          {{/if}}
        </span>

        <span class="kpv-card__info">
          {{#if this.creator}}
            {{! 头像不用 <a>：外层已经是链接，嵌套链接会被浏览器拆散，
                留下的 data-user-card 会让卡片任意位置都弹用户资料卡。 }}
            <span class="kpv-card__avatar {{this.creatorClasses}}">
              {{dAvatar this.creator imageSize="medium"}}
            </span>
          {{/if}}

          <span class="kpv-card__text">
            <span class="kpv-card__title">{{this.topic.title}}</span>

            <span class="kpv-card__meta">
              {{! data-user-card 挂在纯文字上：装扮插件靠它画名牌，
                  而这个元素里没有 <img>，核心不会把它当成头像触发器。 }}
              {{#if this.creator}}
                <span class="kpv-card__user" data-user-card={{this.creator.username}}>{{this.username}}</span>
              {{/if}}
              <span class="kpv-card__stat" title="点赞">
                {{dIcon "heart"}}<span>{{this.likes}}</span>
              </span>
              <span class="kpv-card__stat" title="回复">
                {{dIcon "comment"}}<span>{{this.replies}}</span>
              </span>
              <span class="kpv-card__stat" title="观看">
                {{dIcon "eye"}}<span>{{this.views}}</span>
              </span>
              <span class="kpv-card__time">{{dFormatDate this.topic.bumpedAt format="tiny" noTitle="true"}}</span>
            </span>
          </span>
        </span>
      </a>
    </td>
  </template>
}

