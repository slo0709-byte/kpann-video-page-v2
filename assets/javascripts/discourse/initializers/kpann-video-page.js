import { apiInitializer } from "discourse/lib/api";
import KpannImmersiveButton from "discourse/plugins/kpann-video-page/discourse/components/kpann-immersive-button";

// 视频页的两件事：
// 1. 给 body 挂「视频分类」作用域类（列表/内页样式以它为准）
// 2. 后退规则：从沉浸页退出回当前那条视频的内页；从视频内页后退一次回列表
export default apiInitializer((api) => {
  // 动作排的「沉浸」按钮：官方 post-menu-buttons DAG，平铺页和嵌套页共用
  api.registerValueTransformer("post-menu-buttons", ({ value }) => {
    value.add("kpann-immersive", KpannImmersiveButton);
  });

  const siteSettings = api.container.lookup("service:site-settings");

  const galleryCategoryIds = () =>
    String(siteSettings.kpann_gallery_categories || "")
      .split("|")
      .filter(Boolean)
      .map(Number);

  const syncGalleryScope = () => {
    const ids = galleryCategoryIds();
    let categoryId = null;

    try {
      const router = api.container.lookup("service:router");
      categoryId = router.currentRoute?.attributes?.category?.id ?? null;
    } catch (e) {
      // 拿不到就走下面的兜底
    }

    if (!categoryId) {
      try {
        const model = api.container.lookup("controller:topic")?.model;
        categoryId = model?.category?.id ?? model?.category_id ?? null;
      } catch (e) {
        // 拿不到就走下面的兜底
      }
    }

    if (!categoryId) {
      const m = window.location.pathname.match(/\/c\/[^/]+\/(\d+)/);
      if (m) {
        categoryId = Number(m[1]);
      }
    }

    const inScope = !!categoryId && ids.includes(Number(categoryId));
    document.body.classList.toggle("category-gallery", inScope);
  };

  let lastPath = window.location.pathname;

  api.onPageChange(() => {
    lastPath = window.location.pathname;
    syncGalleryScope();
    setTimeout(syncGalleryScope, 400);
  });

  if (!window.__kpvBackGuard) {
    window.__kpvBackGuard = true;

    window.addEventListener("popstate", () => {
      const from = lastPath || "";

      // 沉浸页退出：回到当前正在看的那条视频内页
      if (from.startsWith("/shorts")) {
        const slides = Array.from(document.querySelectorAll(".kp-slide"));
        const inView = slides.find((el) => {
          const r = el.getBoundingClientRect();
          return r.top >= -60 && r.top < window.innerHeight * 0.6;
        });
        const slide = inView || slides[0];
        const link = slide?.querySelector('a[href*="/t/"]');
        let href = link?.getAttribute("href");
        if (href) {
          let videos = [];
          try {
            videos = JSON.parse(slide.dataset.videos || "[]");
          } catch (e) {
            videos = [];
          }
          const embed = slide.querySelector(".kp-slide__holder")?.dataset.embed;
          const index = videos.findIndex((v) => v.embed === embed);
          if (index > 0) {
            href += (href.includes("?") ? "&" : "?") + "kpv=" + index;
          }
          window.location.replace(href);
        }
        return;
      }

      // 视频内页后退：一次回视频列表页
      let tries = 0;
      const tick = () => {
        tries += 1;
        if (!window.location.pathname.startsWith("/t/")) {
          return;
        }
        const stage = document.querySelector(".kpv");
        const link = document.querySelector(".topic-category a[href^='/c/']");
        if (stage && link) {
          window.location.replace(link.getAttribute("href"));
          return;
        }
        if (tries < 12) {
          setTimeout(tick, 120);
        }
      };
      setTimeout(tick, 120);
    });
  }
});


