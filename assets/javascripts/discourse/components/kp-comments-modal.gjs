import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { getOwner } from "@ember/owner";
import DModal from "discourse/components/d-modal";
import DButton from "discourse/components/d-button";
import Nested from "discourse/components/nested";
import { ajax } from "discourse/lib/ajax";
import ComposerInteractions from "discourse/plugins/kpann-video-page/discourse/lib/composer-interactions";
import PostActions from "discourse/plugins/kpann-video-page/discourse/lib/post-actions";
import NestedTopicController from "discourse/plugins/kpann-video-page/discourse/lib/nested-topic-controller";
import KpCommentPost from "discourse/plugins/kpann-video-page/discourse/components/kp-comment-post";

export default class KpCommentsModal extends Component {
  @service store;
  @service composer;
  @service currentUser;
  @service router;
  @service dialog;
  @service site;
  @service siteSettings;
  @service appEvents;
  @service modal;
  @service messageBus;

  @tracked topicModel = null;
  @tracked tree = [];
  @tracked loading = true;
  @tracked errorText = null;
  @tracked resolvedTitle = null;
  @tracked resolvedAcceptedAnswer = false;
  @tracked isNestedView = false;

  initialPositioning = false;
  showExtraWidgets = false;
  activeSubModal = null;
  fkMenuCloseTimer = null;
  overlayWatcher = {
    open: false,
    syncImmediate() {},
  };
  timingTracker = { trackView() {} };

  _ci = null;
  _pa = null;
  _nested = null;

  constructor() {
    super(...arguments);
    this.composerInteractions.start();
    this.messageBus.subscribe(
      `/topic/${this.topicId}`,
      this.handleTopicMessage
    );
    this._composerWatcher = () => {
      if (!this.composerInteractions.composerOpen) {
        this.composer.skipJumpOnSave = false;
      }
    };
    this.composer.addObserver("model.composeState", this._composerWatcher);
    this.load();
  }

  willDestroy() {
    this.messageBus.unsubscribe(
      `/topic/${this.topicId}`,
      this.handleTopicMessage
    );
    this.composer.removeObserver("model.composeState", this._composerWatcher);
    this.composerInteractions.stop();
    super.willDestroy(...arguments);
  }

  get composerInteractions() {
    if (!this._ci) this._ci = new ComposerInteractions(this);
    return this._ci;
  }

  get postActions() {
    if (!this._pa) this._pa = new PostActions(this);
    return this._pa;
  }

  get nested() {
    if (!this._nested) this._nested = new NestedTopicController(this);
    return this._nested;
  }

  get postStream() {
    return this.topicModel?.postStream;
  }

  get topicId() {
    return this.args.model.topicId;
  }

  get topic() {
    return { id: this.topicId, slug: this.args.model.slug || "" };
  }

  get isNested() {
    return this.isNestedView || !!this.topicModel?.is_nested_view;
  }

  get composerOpen() {
    return this.composerInteractions.composerOpen;
  }

  // 编辑器打开时不要被“点击外部”关掉：编辑器在弹窗外，点它等于点外面
  get dismissable() {
    return !this.activeSubModal && !this.composerOpen;
  }

  get canCreatePost() {
    return !!this.topicModel?.details?.can_create_post;
  }

  get count() {
    if (this.isNested) {
      return (this.nested.rootNodes?.length || 0);
    }
    let n = 0;
    this.tree.forEach((node) => {
      n += 1 + (node.children?.length || 0);
    });
    return n;
  }

  // 标题里的回复数按整帖算（含楼中楼），首楼不算
  get replyCount() {
    const total = this.topicModel?.posts_count;
    if (total && total > 0) {
      return Math.max(0, total - 1);
    }
    return this.count;
  }

  get title() {
    return `回复 ${this.replyCount}`;
  }

  get topicController() {
    try {
      return getOwner(this).lookup("controller:topic");
    } catch (e) {
      return null;
    }
  }

  adoptTopicController() {
    const controller = this.topicController;
    if (!controller || !this.topicModel) return;
    if (this.router.currentRouteName?.startsWith("topic.")) return;
    controller.set("model", this.topicModel);
  }

  closeModal() {
    this.args.closeModal?.();
  }

  closeSubModal() {
    this.activeSubModal = null;
  }

  showSubModal(component, model) {
    this.modal.show(component, { model });
  }

  openFull() {
    const slug = this.topicModel?.slug || this.args.model.slug || "topic";
    window.location.assign(`/t/${slug}/${this.topicId}`);
  }

  @action
  showLogin() {
    this.args.closeModal?.();
    window.location.assign("/login");
  }

  // 发完回复不跳走：留在沉浸页，关掉编辑器后回到面板
  @action
  replyToTopic() {
    this.composer.skipJumpOnSave = true;
    return this.composerInteractions.replyToTopic();
  }

  @action
  replyToPost(post) {
    this.composer.skipJumpOnSave = true;
    return this.composerInteractions.replyToPost(post);
  }

  handleTopicMessage = (data) => {
    if (this.isDestroying || this.isDestroyed || !data?.id) {
      return;
    }
    if (this.isNested) {
      this.nested.handleTopicMessage(data);
      return;
    }
    if (!this.postStream) {
      return;
    }
    if (data.type === "created") {
      Promise.resolve(this.postStream.triggerNewPostsInStream(data.id)).catch(
        () => {}
      );
      return;
    }
    this.postStream.loadPost(data.id).catch(() => {});
  };

  buildTree(posts) {
    const nodes = posts.map((post) => ({ post, children: [] }));
    const byNumber = new Map(nodes.map((n) => [n.post.post_number, n]));
    const roots = [];
    nodes.forEach((node) => {
      const parentNumber = node.post.reply_to_post_number;
      const parent = parentNumber ? byNumber.get(parentNumber) : null;
      if (parent) parent.children.push(node);
      else roots.push(node);
    });
    return roots;
  }

  async load() {
    try {
      let topic = null;
      try {
        topic = this.store.createRecord("topic", {
          id: this.topicId,
          slug: this.args.model.slug || "",
        });
      } catch (e) {
        topic = await this.store.find("topic", this.topicId);
      }

      await topic.postStream.refresh({
        forceLoad: true,
        track_visit: false,
        nearPost: 2,
      });

      this.topicModel = topic;

      try {
        const json = await ajax(`/t/${this.topicId}.json`, {
          data: { track_visit: false },
        });
        if (json?.details) topic.set("details", json.details);
        this.isNestedView = !!json?.is_nested_view;
      } catch (e) {}

      this.adoptTopicController();

      if (this.isNested) {
        await this.nested.finishLoad();
      } else {
        const posts = (topic.postStream?.posts || []).filter(
          (p) => p.post_number > 1
        );
        this.tree = this.buildTree(posts);
      }
    } catch (e) {
      this.errorText = String(e && e.message ? e.message : e);
      this.tree = [];
    }
    this.loading = false;
  }

  <template>
    <DModal
      @title={{this.title}}
      @closeModal={{@closeModal}}
      @autofocus={{false}}
      @dismissable={{this.dismissable}}
      @hidden={{this.composerOpen}}
      class={{if
        this.composerOpen
        "kp-comments-modal kp-comments-modal--composer-open"
        "kp-comments-modal"
      }}
    >
      <:body>
        {{#if this.loading}}
          <div class="kp-comments-modal__loading">加载中…</div>
        {{else if this.isNested}}
          <div class="kp-comments-modal__nested">
            <Nested
              @topic={{this.topicModel}}
              @opPost={{this.nested.opPost}}
              @rootNodes={{this.nested.rootNodes}}
              @sort={{this.nested.sort}}
              @effectiveSort={{this.nested.effectiveSort}}
              @hasMoreRoots={{this.nested.hasMoreRoots}}
              @loadingMore={{this.nested.loadingMore}}
              @pinnedPostIds={{this.nested.pinnedPostIds}}
              @loadMoreRoots={{this.nested.loadMoreRoots}}
              @changeSort={{this.nested.changeSort}}
              @replyToPost={{this.replyToPost}}
              @editPost={{this.composerInteractions.editPost}}
              @deletePost={{this.postActions.deletePost}}
              @recoverPost={{this.postActions.recoverPost}}
              @showFlags={{this.postActions.showFlags}}
              @showHistory={{this.postActions.showHistory}}
              @changeNotice={{this.postActions.changeNotice}}
              @changePostOwner={{this.postActions.changePostOwner}}
              @grantBadge={{this.postActions.grantBadge}}
              @lockPost={{this.postActions.lockPost}}
              @unlockPost={{this.postActions.unlockPost}}
              @permanentlyDeletePost={{this.postActions.permanentlyDeletePost}}
              @rebakePost={{this.postActions.rebakePost}}
              @togglePostType={{this.postActions.togglePostType}}
              @toggleWiki={{this.postActions.toggleWiki}}
              @unhidePost={{this.postActions.unhidePost}}
              @expansionState={{this.nested.expansionState}}
              @fetchedChildrenCache={{this.nested.fetchedChildrenCache}}
              @selectReplies={{this.postActions.selectReplies}}
              @selectBelow={{this.postActions.selectBelow}}
              @contextMode={{false}}
            />
          </div>
        {{else if this.tree.length}}
          <div class="kp-comments-modal__list">
            {{#each this.tree as |node|}}
              <div class="kp-comments-modal__post">
                <KpCommentPost @post={{node.post}} @ctx={{this}} />
              </div>
            {{/each}}
          </div>
        {{else}}
          <div class="kp-comments-modal__empty">还没有回复</div>
          {{#if this.errorText}}
            <div class="kp-comments-modal__empty">错误：{{this.errorText}}</div>
          {{/if}}
        {{/if}}
      </:body>

      <:footer>
        <div class="kp-comments-modal__footer">
          <DButton
            class="btn-primary"
            @icon="reply"
            @label="js.composer.reply"
            @action={{this.replyToTopic}}
          />
        </div>
      </:footer>
    </DModal>
  </template>
}
