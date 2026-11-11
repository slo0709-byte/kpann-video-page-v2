import { apiInitializer } from "discourse/lib/api";

// 视频分类的列表卡片，全部走官方扩展点：
//  · topic-list-class       给表格加一个自己的类，样式只认这个类
//  · topic-list-item outlet 整行接管（见 connectors/topic-list-item/）
// 行元素仍是核心的 <tr>，所以悬停、批量选择、整行点击都保持原生。
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

  // 行的内容改由 connectors/topic-list-item 整行接管（官方 wrapper outlet）。
  // 这里只保留「列表加个自己的类」，用来给表格容器做栅格排布。
  // 不再替换列：换主题时列网格会消失，卡片会被压成 0 宽。
});
