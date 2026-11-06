import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import dIcon from "discourse/ui-kit/helpers/d-icon";

import KpSlideExcerpt from "discourse/plugins/kpann-video-page/discourse/components/kp-slide-excerpt";
import KpSlideAuthor from "discourse/plugins/kpann-video-page/discourse/components/kp-slide-author";

const LIKE_ACTION_ID = 2;
const UNDO_EXPIRED_MESSAGE = "这条已经点过赞了，超过 10 分钟就不能取消。";
const STALE_MESSAGE = "点赞状态已经变了，刷新页面后再点一次。";

export default class ShortsPage extends Component {
  @service currentUser;
  @service siteSettings;
  @service dialog;

  @tracked likeState = {};

  // 返回：回到当前这条视频的帖子页（不走浏览器历史，免得退回列表或别的页）
  @action
  goBack() {
    const fromQuery = new URLSearchParams(window.location.search).get("topic");
    const slides = [...document.querySelectorAll(".kp-slide")];
    const track = document.querySelector(".kp-shorts__track");
    let slide = fromQuery
      ? slides.find((s) => String(s.dataset.topicId) === String(fromQuery))
      : null;
    if (!slide && track && slides.length) {
      const index = Math.round(track.scrollTop / (track.clientHeight || 1));
      slide = slides[index] || slides[0];
    }
    const link = slide?.querySelector('a[href^="/t/"]');
    if (link) {
      window.location.assign(this.#withEpisode(slide, link.getAttribute("href")));
      return;
    }
    window.location.assign("/");
  }

  // 沉浸页里换过集之后，退出 / 打开帖子都要带着当前这一集回内页（?kpv=N）
  #withEpisode(slide, href) {
    if (!slide || !href) {
      return href;
    }
    let videos = [];
    try {
      videos = JSON.parse(slide.dataset.videos || "[]");
    } catch (e) {
      videos = [];
    }
    const embed = slide.querySelector(".kp-slide__holder")?.dataset.embed;
    const index = videos.findIndex((video) => video.embed === embed);
    if (index <= 0) {
      return href;
    }
    return `${href}${href.includes("?") ? "&" : "?"}kpv=${index}`;
  }

  @action
  openTopic(event) {
    event.preventDefault();
    const link = event.currentTarget;
    window.location.assign(
      this.#withEpisode(link.closest(".kp-slide"), link.getAttribute("href"))
    );
  }
  @action
  likesFor(slide) {
    return this.likeState[slide.id]?.count ?? slide.likes;
  }

  @action
  likeClass(slide) {
    return `kp-act kp-act--like${this.likedFor(slide) ? " is-liked" : ""}`;
  }

  @action
  likedFor(slide) {
    return this.likeState[slide.id]?.liked ?? slide.liked;
  }

  @action
  async toggleLike(event) {
    const topicId = Number(event.currentTarget?.dataset?.topic);
    const slide = this.args.model.find((item) => item.id === topicId);
    if (!slide) {
      return;
    }

    if (!this.currentUser) {
      DiscourseURL.redirectTo("/login");
      return;
    }

    const current = this.likeState[slide.id];
    if (current?.busy) {
      return;
    }

    // act = 可以赞；undo = 已赞且可撤销；liked = 赞过了但过了撤销时限；none = 无权
    const action = current?.action ?? slide.likeAction;

    if (action === "none") {
      return;
    }

    if (action === "liked") {
      this.dialog.alert(UNDO_EXPIRED_MESSAGE);
      return;
    }

    const before = {
      count: this.likesFor(slide),
      liked: this.likedFor(slide),
      action,
    };

    this.#write(slide.id, {
      count: Math.max(0, before.count + (before.liked ? -1 : 1)),
      liked: !before.liked,
      action: before.liked ? "act" : "undo",
      busy: true,
    });

    try {
      const result = await this.#toggleLikeRequest(slide.postId);
      const liked = this.#likedFrom(result, !before.liked);
      const count =
        typeof result?.like_count === "number"
          ? result.like_count
          : this.likeState[slide.id].count;

      this.#write(slide.id, {
        count,
        liked,
        action: liked ? "undo" : "act",
        busy: false,
      });
    } catch (error) {
      this.#write(slide.id, { ...before, busy: false });

      if (this.#statusOf(error) === 403) {
        this.dialog.alert(STALE_MESSAGE);
      } else {
        popupAjaxError(error);
      }
    }
  }

  // 点赞走官方入口：
  // - 站点装了 discourse-reactions（本站开着），点赞就是 heart 这个 reaction，
  //   官方前端组件的做法就是 PUT 这个 toggle 接口（discourse-reactions 的 CustomReaction.toggle）
  // - 没装的时候退回原生 POST /post_actions（post_action_type_id=2）
  // 两种情况都不自己拼 CSRF、不自己改数字，请求统一走 discourse/lib/ajax。
  #toggleLikeRequest(postId) {
    if (this.siteSettings.discourse_reactions_enabled) {
      const reaction =
        this.siteSettings.discourse_reactions_reaction_for_like || "heart";
      return ajax(
        `/discourse-reactions/posts/${postId}/custom-reactions/${reaction}/toggle.json`,
        { type: "PUT" }
      );
    }

    return ajax("/post_actions", {
      type: "POST",
      data: { id: postId, post_action_type_id: LIKE_ACTION_ID },
    });
  }

  #likedFrom(result, fallback) {
    if (result?.current_user_reaction) {
      return true;
    }

    const summary = (result?.actions_summary || []).find(
      (action) => action.id === LIKE_ACTION_ID
    );

    return summary ? !!summary.acted : fallback;
  }

  #statusOf(error) {
    return error?.jqXHR?.status || error?.status || 0;
  }

  #write(topicId, state) {
    this.likeState = { ...this.likeState, [topicId]: state };
  }

  <template>
    <div class="kp-shorts">
      <header class="kp-shorts__bar">
        <button type="button" class="kp-shorts__back" title="返回" {{on "click" this.goBack}}>
          {{dIcon "arrow-left"}}
        </button>
        <span class="kp-shorts__label">沉浸模式</span>
      </header>

      <div class="kp-shorts__track">
        {{#each @model as |t|}}
          <section
            class="kp-slide"
            data-topic-id={{t.id}}
            data-videos={{t.videosJson}}
          >
            <div class="kp-slide__stage">
              <div class="kp-slide__holder" data-embed={{t.embed}}>
                {{#if t.cover}}
                  <img class="kp-slide__poster" src={{t.cover}} alt={{t.title}}>
                {{/if}}
              </div>
            </div>

            <div class="kp-slide__side">
              {{#if t.hasCollection}}
                <button
                  type="button"
                  class="kp-act kp-act--collection"
                  data-topic={{t.id}}
                  title="合集"
                >
                  {{dIcon "list"}}<span>{{t.videoCount}}</span>
                </button>
              {{/if}}
              <button
                type="button"
                class={{this.likeClass t}}
                data-topic={{t.id}}
                title="赞"
                {{on "click" this.toggleLike}}
              >
                {{dIcon "heart"}}<span>{{this.likesFor t}}</span>
              </button>
              <button type="button" class="kp-act kp-act--comment" data-topic={{t.id}} data-slug={{t.slug}} title="评论">
                {{dIcon "comment"}}<span>{{t.posts}}</span>
              </button>
              <a class="kp-act" href="/t/{{t.slug}}/{{t.id}}" title="打开帖子" {{on "click" this.openTopic}}>
                {{dIcon "link"}}
              </a>
            </div>

            <div class="kp-slide__meta">
              <div class="kp-slide__author names">
                <KpSlideAuthor
                  @username={{t.posterName}}
                  @avatarUrl={{t.posterAvatar}}
                  @posterId={{t.posterId}}
                />
              </div>
              <div class="kp-slide__title">{{t.title}}</div>
              {{#if t.excerpt}}
                <KpSlideExcerpt @text={{t.excerpt}} />
              {{/if}}
            </div>
          </section>
        {{/each}}
      </div>
    </div>
  </template>
}
