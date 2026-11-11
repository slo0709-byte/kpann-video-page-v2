import Component from "@glimmer/component";
import { service } from "@ember/service";

import KpannVideoCard from "discourse/plugins/kpann-video-page/discourse/components/kpann-video-card";

// 视频分类的列表行：接管整行内容（官方 topic-list-item wrapper outlet）。
// 不在视频分类页就 {{yield}}，把核心原来的行原样还给核心。
//
// 判断依据是「当前页面是不是这个分类的列表」，不是「这条话题属于哪个分类」。
// 用后者的话，首页 / 最新 / 未读 这类混合列表里只要有一条视频帖，
// 那一行就会被换成大卡片，整张表跟着变形——这就是用户报的「其他页面也显示视频卡片」。
//
// 为什么接管整行：
//   之前用 topic-list-columns 只换「标题」列，行的网格由主题提供；
//   换到没有那套网格的主题，行退回原生 table-row、卡片被压成 0 宽。
//   整行接管后外观自己画，换主题只影响颜色和字体。
export default class KpannTopicListItem extends Component {
  @service siteSettings;
  @service router;

  get galleryIds() {
    return String(this.siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);
  }

  // 当前路由必须是分类列表页，且该分类在 kpann_gallery_categories 里
  get inGalleryList() {
    const ids = this.galleryIds;
    if (!ids.length) {
      return false;
    }

    const routeName = this.router.currentRouteName;
    if (!routeName || !routeName.startsWith("discovery.category")) {
      return false;
    }

    // category_slug_path_with_id 形如 "video/5" 或 "parent/sub/12"
    const param = String(
      this.router.currentRoute?.params?.category_slug_path_with_id || ""
    );
    const id = Number(param.split("/").filter(Boolean).pop());
    if (!id || !ids.includes(id)) {
      return false;
    }

    // 视频分类里的每一行都画成卡片，保持栅格整齐；
    // 没抓到封面的（分类说明帖、纯文字帖）由卡片自己显示占位图标。
    // 不能把个别行交还给核心原生行：表格是 grid 布局，
    // 原生行在里面没有列宽，会显示成小头像 + 数字挤在一起。
    return true;
  }

  <template>
    {{#if this.inGalleryList}}
      <KpannVideoCard @outletArgs={{@outletArgs}} />
    {{else}}
      {{yield}}
    {{/if}}
  </template>
}

