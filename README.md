# kpann-video-page v1.4

Discourse 插件：视频列表卡片、视频内页版式、沉浸模式（/shorts）。

## 安装

1. 把本仓库放进 `plugins/kpann-video-page`（目录名必须一致）。
2. 在 `containers/app.yml` 的钩子里加两行（嵌套视图版式需要）：

   ```
   - cp -f /shared/plugins/kpann-video-page/core-patches/components/nested.gjs $home/frontend/discourse/app/components/nested.gjs
   - cp -f /shared/plugins/kpann-video-page/core-patches/components/nested/op.gjs $home/frontend/discourse/app/components/nested/op.gjs
   ```

3. 后台开启 `kpann_video_page_enabled`，把 `kpann_gallery_categories` 设为视频分类 id（默认 190）。
4. 重建一次；老帖需要重新保存首楼（或跑一次回填）才会写入 `kpann_videos`。

## 说明

- 视频元数据（封面/播放地址/时长/一帖多视频）由本插件自己抓取，不依赖其它插件。
- 动作排的点赞按钮来自官方 `discourse-reactions`（可选）。
- 沉浸入口走官方 `post-menu-buttons` DAG 注册；「观看」与「展开全文」走官方插件 outlet。
