import { apiInitializer } from "discourse/lib/api";
import KpannVideoCard from "discourse/plugins/kpann-video-page/discourse/components/kpann-video-card";

// 视频分类的列表卡片，全部走官方扩展点（照 Horizon / JTech 同款做法）：
//  · topic-list-class       给表格加一个自己的类，样式只认这个类
//  · topic-list-columns     把「标题」列换成视频卡片，其余列（头像/回复/点赞/浏览/时间）删掉
//  · topic-list-item-mobile-layout  返回 false，让手机也用同一套列，双端一个组件
// 行结构始终是核心的，所以悬停、批量选择、悬停预览、整行点击都保持原生。
export default apiInitializer((api) => {
  const siteSettings = api.container.lookup("service:site-settings");

  const galleryIds = () =>
    String(siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);

  const inGallery = (context) => {
    const id = Number(context?.category?.id);
    return !!id && galleryIds().includes(id);
  };

  api.registerValueTransformer("topic-list-class", ({ value, context }) => {
    if (inGallery(context)) {
      value.push("kpv-video-list");
    }
    return value;
  });

  api.registerValueTransformer(
    "topic-list-columns",
    ({ value: columns, context }) => {
      if (!inGallery(context)) {
        return columns;
      }

      ["posters", "replies", "likes", "op-likes", "views", "activity"].forEach(
        (key) => columns.delete(key)
      );
      columns.replace("topic", { item: KpannVideoCard });

      return columns;
    }
  );

  api.registerValueTransformer(
    "topic-list-item-mobile-layout",
    ({ value, context }) => (inGallery(context) ? false : value)
  );
});
