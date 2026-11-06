import Post from "discourse/components/post";

export default <template>
  <Post
    @post={{@post}}
    @canCreatePost={{true}}
    @showReadIndicator={{false}}
    @editPost={{@ctx.postActions.editPost}}
    @deletePost={{@ctx.postActions.deletePost}}
    @recoverPost={{@ctx.postActions.recoverPost}}
    @permanentlyDeletePost={{@ctx.postActions.permanentlyDeletePost}}
    @showFlags={{@ctx.postActions.showFlags}}
    @showHistory={{@ctx.postActions.showHistory}}
    @grantBadge={{@ctx.postActions.grantBadge}}
    @changeNotice={{@ctx.postActions.changeNotice}}
    @changePostOwner={{@ctx.postActions.changePostOwner}}
    @lockPost={{@ctx.postActions.lockPost}}
    @unlockPost={{@ctx.postActions.unlockPost}}
    @rebakePost={{@ctx.postActions.rebakePost}}
    @togglePostType={{@ctx.postActions.togglePostType}}
    @toggleWiki={{@ctx.postActions.toggleWiki}}
    @unhidePost={{@ctx.postActions.unhidePost}}
    @expandHidden={{@ctx.postActions.expandHidden}}
    @replyToPost={{@ctx.composerInteractions.replyToPost}}
    @showLogin={{@ctx.showLogin}}
    @showInvite={{false}}
    @showRawEmail={{@ctx.postActions.showRawEmail}}
    @selectReplies={{@ctx.postActions.selectReplies}}
    @selectBelow={{@ctx.postActions.selectBelow}}
    @cancelFilter={{@ctx.postActions.cancelFilter}}
    @showPagePublish={{false}}
  />
</template>
