(function () {
  "use strict";

  const sidebar = document.getElementById("sidebar");
  const overlay = document.getElementById("mobileOverlay");
  const menuBtn = document.getElementById("menuBtn");
  const sidebarClose = document.getElementById("sidebarClose");
  const navLinks = document.querySelectorAll(".nav-link");

  function setSidebarOpen(open) {
    if (!sidebar || !overlay) return;
    sidebar.classList.toggle("show", open);
    overlay.classList.toggle("show", open);
  }

  if (menuBtn) {
    menuBtn.addEventListener("click", function () {
      setSidebarOpen(true);
    });
  }

  if (sidebarClose) {
    sidebarClose.addEventListener("click", function () {
      setSidebarOpen(false);
    });
  }

  if (overlay) {
    overlay.addEventListener("click", function () {
      setSidebarOpen(false);
    });
  }

  navLinks.forEach(function (link) {
    link.addEventListener("click", function () {
      if (window.innerWidth <= 860) {
        setSidebarOpen(false);
      }
    });
  });

  const mobileBottomNav = document.querySelector(".mobile-bottom-nav");
  const mobileQuickActionBtn = document.getElementById("mobileQuickActionBtn");
  const mobileQuickActions = document.getElementById("mobileQuickActions");

  function setQuickActionsOpen(open) {
    if (!mobileBottomNav || !mobileQuickActionBtn) return;
    mobileBottomNav.classList.toggle("is-quick-open", open);
    mobileQuickActionBtn.setAttribute("aria-expanded", open ? "true" : "false");
  }

  if (mobileQuickActionBtn && mobileBottomNav) {
    mobileQuickActionBtn.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      setQuickActionsOpen(!mobileBottomNav.classList.contains("is-quick-open"));
    });
  }

  if (mobileQuickActions) {
    mobileQuickActions.addEventListener("click", function (event) {
      event.stopPropagation();
      const target = event.target;
      if (target instanceof Element && target.closest("a")) {
        setQuickActionsOpen(false);
      }
    });
  }

  document.addEventListener("click", function (event) {
    if (!mobileBottomNav || !mobileBottomNav.classList.contains("is-quick-open")) {
      return;
    }
    if (event.target instanceof Node && mobileBottomNav.contains(event.target)) {
      return;
    }
    setQuickActionsOpen(false);
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      setQuickActionsOpen(false);
    }
  });

  /* Hide mobile bottom nav when any offcanvas (side panel) is open */
  document.addEventListener("shown.bs.offcanvas", function () {
    document.body.classList.add("offcanvas-open");
  });
  document.addEventListener("hidden.bs.offcanvas", function () {
    document.body.classList.remove("offcanvas-open");
  });

  window.addEventListener("resize", function () {
    if (window.innerWidth > 860) {
      setSidebarOpen(false);
      setQuickActionsOpen(false);
    }
  });

  const liveClock = document.getElementById("liveClock");
  const liveDate = document.getElementById("liveDate");
  const topbarDate = document.getElementById("topbarDate");

  if (topbarDate) {
    topbarDate.textContent = new Date().toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric"
    });
  }

  if (liveClock && liveDate) {
    function tick() {
      const now = new Date();
      liveClock.textContent = now.toLocaleTimeString();
      liveDate.textContent = now.toDateString();
    }

    tick();
    setInterval(tick, 1000);
  }

  const leaveForm = document.getElementById("leaveForm");
  if (leaveForm) {
    leaveForm.addEventListener("submit", function (event) {
      event.preventDefault();
      alert("Demo mode: this request form is now on a separate page. Backend submit can be added next.");
    });
  }

  const confirmModalEl = document.getElementById("globalConfirmModal");
  const confirmModalTitle = document.getElementById("globalConfirmModalTitle");
  const confirmModalMsg = document.getElementById("globalConfirmModalMessage");
  const confirmModalSubmit = document.getElementById("globalConfirmModalSubmit");
  const confirmReasonWrap = document.getElementById("globalConfirmReasonWrap");
  const confirmReasonLabel = document.getElementById("globalConfirmReasonLabel");
  const confirmReasonInput = document.getElementById("globalConfirmReasonInput");
  const confirmReasonError = document.getElementById("globalConfirmReasonError");
  const defaultConfirmTitle = "Confirm Action";
  const defaultConfirmMessage = "Are you sure you want to continue?";
  const defaultConfirmSubmitText = "Confirm";
  let pendingConfirmForm = null;
  let confirmModal = null;

  if (confirmModalEl && window.bootstrap && typeof window.bootstrap.Modal === "function") {
    confirmModal = new window.bootstrap.Modal(confirmModalEl);
  }

  function buildConfirmMessage(form) {
    const template = form.getAttribute("data-confirm-template");
    const staticMessage = form.getAttribute("data-confirm-message");

    if (template) {
      const statusInput = form.querySelector("[name='status']");
      const statusValue = statusInput ? (statusInput.value || "").trim() : "";
      if (statusValue) {
        return template.replace("{status}", statusValue.toLowerCase());
      }
      return template.replace("{status}", "this status");
    }

    return staticMessage || defaultConfirmMessage;
  }

  function setConfirmSubmitVariant(variantName) {
    if (!confirmModalSubmit) {
      return;
    }

    const variant = (variantName || "primary").toLowerCase();
    confirmModalSubmit.classList.remove("confirm-btn-submit", "confirm-btn-success", "confirm-btn-danger");

    if (variant === "danger") {
      confirmModalSubmit.classList.add("confirm-btn-danger");
      return;
    }

    if (variant === "success") {
      confirmModalSubmit.classList.add("confirm-btn-success");
      return;
    }

    confirmModalSubmit.classList.add("confirm-btn-submit");
  }

  function resetConfirmModalUi() {
    if (confirmModalTitle) {
      confirmModalTitle.textContent = defaultConfirmTitle;
    }
    if (confirmModalMsg) {
      confirmModalMsg.textContent = defaultConfirmMessage;
    }
    if (confirmModalSubmit) {
      confirmModalSubmit.textContent = defaultConfirmSubmitText;
    }
    setConfirmSubmitVariant("primary");
  }

  function resetConfirmReasonUi() {
    if (confirmReasonWrap) {
      confirmReasonWrap.classList.add("d-none");
    }
    if (confirmReasonInput) {
      confirmReasonInput.value = "";
      confirmReasonInput.classList.remove("is-invalid");
    }
    if (confirmReasonError) {
      confirmReasonError.classList.add("d-none");
    }
    if (confirmReasonLabel) {
      confirmReasonLabel.textContent = "Please enter reason why:";
    }
  }

  function openConfirmForForm(form) {
    if (!confirmModal || !confirmModalMsg || !confirmModalSubmit) {
      return;
    }

    pendingConfirmForm = form;
    resetConfirmModalUi();
    if (confirmModalTitle) {
      confirmModalTitle.textContent = form.getAttribute("data-confirm-title") || defaultConfirmTitle;
    }
    confirmModalMsg.textContent = buildConfirmMessage(form);
    confirmModalSubmit.textContent = form.getAttribute("data-confirm-confirm-text") || defaultConfirmSubmitText;
    setConfirmSubmitVariant(form.getAttribute("data-confirm-variant"));
    resetConfirmReasonUi();

    if (form.getAttribute("data-require-reason") === "true") {
      const reasonPrompt = form.getAttribute("data-reason-prompt") || "Please enter reason why:";
      const reasonField = form.getAttribute("data-reason-field") || "reject_reason";
      const reasonHiddenInput = form.querySelector(`[name='${reasonField}']`);

      if (confirmReasonWrap) {
        confirmReasonWrap.classList.remove("d-none");
      }
      if (confirmReasonLabel) {
        confirmReasonLabel.textContent = reasonPrompt;
      }
      if (confirmReasonInput) {
        confirmReasonInput.value = reasonHiddenInput ? (reasonHiddenInput.value || "").trim() : "";
      }
    }

    confirmModal.show();
  }

  document.addEventListener("submit", function (event) {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    if (form.getAttribute("data-confirm-action") !== "true") {
      return;
    }

    if (form.dataset.confirmed === "true") {
      form.dataset.confirmed = "false";
      return;
    }

    event.preventDefault();

    if (!confirmModal || !confirmModalMsg || !confirmModalSubmit) {
      return;
    }

    openConfirmForForm(form);
  });

  if (confirmModalEl) {
    confirmModalEl.addEventListener("shown.bs.modal", function () {
      if (confirmModalSubmit) {
        confirmModalSubmit.focus();
      }
    });

    confirmModalEl.addEventListener("hidden.bs.modal", function () {
      pendingConfirmForm = null;
      resetConfirmModalUi();
      resetConfirmReasonUi();
    });
  }

  function submitFormViaAjax(form) {
    const formData = new FormData(form);
    fetch(form.action, {
      method: form.method || "POST",
      body: formData,
      headers: {
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(function (response) {
        if (!response.ok) {
          return response.json().then(function (data) {
            throw new Error(data.message || "Request failed");
          }).catch(function () {
            throw new Error("Request failed");
          });
        }
        return response.json();
      })
      .then(function (data) {
        if (data.success) {
          if (window.HYGToast) {
            HYGToast.show("success", data.message);
          }
          const modalEl = form.closest(".modal");
          if (modalEl && window.bootstrap && bootstrap.Modal) {
            const modal = bootstrap.Modal.getInstance(modalEl);
            if (modal) modal.hide();
          }
          window.location.reload();
        } else {
          if (window.HYGToast) {
            HYGToast.show("error", data.message);
          }
        }
      })
      .catch(function (error) {
        if (window.HYGToast) {
          HYGToast.show("error", error.message || "An error occurred while saving. Please try again.");
        }
      });
  }

  if (confirmModalSubmit) {
    confirmModalSubmit.addEventListener("click", function () {
      if (!pendingConfirmForm) {
        return;
      }

      if (pendingConfirmForm.getAttribute("data-require-reason") === "true") {
        const reasonField = pendingConfirmForm.getAttribute("data-reason-field") || "reject_reason";
        let reasonInput = pendingConfirmForm.querySelector(`[name='${reasonField}']`);

        if (!reasonInput) {
          reasonInput = document.createElement("input");
          reasonInput.type = "hidden";
          reasonInput.name = reasonField;
          pendingConfirmForm.appendChild(reasonInput);
        }

        const finalReason = confirmReasonInput ? confirmReasonInput.value.trim() : "";
        if (!finalReason) {
          if (confirmReasonError) {
            confirmReasonError.classList.remove("d-none");
          }
          if (confirmReasonInput) {
            confirmReasonInput.classList.add("is-invalid");
            confirmReasonInput.focus();
          }
          return;
        }

        if (confirmReasonError) {
          confirmReasonError.classList.add("d-none");
        }
        if (confirmReasonInput) {
          confirmReasonInput.classList.remove("is-invalid");
        }
        reasonInput.value = finalReason;
      }

      if (typeof pendingConfirmForm.checkValidity === "function" && !pendingConfirmForm.checkValidity()) {
        if (typeof pendingConfirmForm.reportValidity === "function") {
          pendingConfirmForm.reportValidity();
        }
        return;
      }

      if (pendingConfirmForm.getAttribute("data-ajax-submit") === "true") {
        submitFormViaAjax(pendingConfirmForm);
        if (confirmModal) {
          confirmModal.hide();
        }
        return;
      }

      pendingConfirmForm.dataset.confirmed = "true";
      if (typeof pendingConfirmForm.requestSubmit === "function") {
        pendingConfirmForm.requestSubmit();
      } else {
        pendingConfirmForm.submit();
      }
      if (confirmModal) {
        confirmModal.hide();
      }
    });
  }

  const appContent = document.getElementById("appContent");
  const pageCache = new Map();
  let currentController = null;

  function isSameOriginPageLink(link) {
    if (!link || link.dataset.fullReload === "true") return false;
    if (link.target && link.target !== "_self") return false;
    if (link.hasAttribute("download")) return false;

    const url = new URL(link.href, window.location.href);
    if (url.origin !== window.location.origin) return false;
    if (url.hash && url.pathname === window.location.pathname && url.search === window.location.search) return false;

    const hardReloadPaths = ["/logout", "/login", "/register"];
    if (hardReloadPaths.includes(url.pathname)) return false;

    return true;
  }

  function buildSkeleton() {
    return `
      <div class="page-skeleton" aria-hidden="true">
        <div class="skeleton-line is-title"></div>
        <div class="skeleton-line is-short"></div>
        <div class="skeleton-grid">
          <div class="skeleton-card"></div>
          <div class="skeleton-card"></div>
          <div class="skeleton-card"></div>
        </div>
        <div class="skeleton-card"></div>
      </div>
    `;
  }

  function updateActiveNavigation(pathname) {
    document.querySelectorAll(".nav-link, .mobile-nav-link").forEach(function (link) {
      if (!(link instanceof HTMLAnchorElement)) return;
      const url = new URL(link.href, window.location.href);
      const isActive = url.pathname === pathname;
      link.classList.toggle("active", isActive);
      if (isActive) {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    });
  }

  function setContentBusy(isBusy) {
    if (!appContent) return;
    appContent.setAttribute("aria-busy", isBusy ? "true" : "false");
  }

  function showSkeleton() {
    if (!appContent) return;
    setContentBusy(true);
    appContent.classList.add("is-leaving");
    window.setTimeout(function () {
      if (appContent.getAttribute("aria-busy") === "true") {
        appContent.innerHTML = buildSkeleton();
        appContent.classList.remove("is-leaving");
      }
    }, 90);
  }

  function loadDynamicStyles(doc) {
    doc.querySelectorAll("link[rel='stylesheet']").forEach(function (styleLink) {
      const href = styleLink.getAttribute("href");
      if (!href || document.querySelector(`link[rel='stylesheet'][href="${href}"]`)) return;

      const nextLink = document.createElement("link");
      nextLink.rel = "stylesheet";
      nextLink.href = href;
      nextLink.dataset.pwaDynamic = "true";
      document.head.appendChild(nextLink);
    });

    doc.head.querySelectorAll("style").forEach(function (styleTag, index) {
      const cssText = styleTag.textContent || "";
      let hash = 0;

      for (let i = 0; i < cssText.length; i += 1) {
        hash = ((hash << 5) - hash + cssText.charCodeAt(i)) | 0;
      }

      const styleKey = `${index}-${cssText.length}-${Math.abs(hash)}`;
      if (!cssText.trim() || document.querySelector(`style[data-pwa-style-key="${styleKey}"]`)) {
        return;
      }

      const nextStyle = document.createElement("style");
      nextStyle.dataset.pwaDynamic = "true";
      nextStyle.dataset.pwaStyleKey = styleKey;
      nextStyle.textContent = cssText;
      document.head.appendChild(nextStyle);
    });
  }

  function runDynamicScripts(doc) {
    document.querySelectorAll("script[data-pwa-page-script]").forEach(function (script) {
      script.remove();
    });

    doc.body.querySelectorAll("script").forEach(function (script) {
      const src = script.getAttribute("src");
      if (src && document.querySelector(`script[src="${src}"]:not([data-pwa-page-script])`)) {
        return;
      }

      const nextScript = document.createElement("script");
      Array.from(script.attributes).forEach(function (attr) {
        nextScript.setAttribute(attr.name, attr.value);
      });
      nextScript.dataset.pwaPageScript = "true";
      nextScript.textContent = script.textContent;
      document.body.appendChild(nextScript);
    });
  }

  function initDynamicContent() {
    const newLiveClock = document.getElementById("liveClock");
    const newLiveDate = document.getElementById("liveDate");

    if (newLiveClock && newLiveDate) {
      const now = new Date();
      newLiveClock.textContent = now.toLocaleTimeString();
      newLiveDate.textContent = now.toDateString();
    }
  }

  function swapPage(doc, url, shouldPush) {
    if (!appContent) return;

    const nextContent = doc.querySelector("#appContent") || doc.querySelector("main.page");
    if (!nextContent) {
      window.location.href = url.href;
      return;
    }

    loadDynamicStyles(doc);
    document.title = doc.title || document.title;
    appContent.innerHTML = nextContent.innerHTML;
    appContent.classList.remove("is-leaving");
    appContent.classList.add("is-entering");
    setContentBusy(false);
    window.setTimeout(function () {
      appContent.classList.remove("is-entering");
    }, 220);

    updateActiveNavigation(url.pathname);
    runDynamicScripts(doc);
    initDynamicContent();

    if (shouldPush) {
      history.pushState({ url: url.href }, "", url.href);
    }

    if (window.innerWidth <= 860) {
      setSidebarOpen(false);
      setQuickActionsOpen(false);
    }

    window.scrollTo({ top: 0, behavior: "instant" in document.documentElement.style ? "instant" : "auto" });
  }

  async function fetchPage(url) {
    const cacheKey = url.pathname + url.search;
    if (pageCache.has(cacheKey)) {
      return pageCache.get(cacheKey).cloneNode(true);
    }

    if (currentController) {
      currentController.abort();
    }
    currentController = new AbortController();

    const response = await fetch(url.href, {
      headers: {
        "X-Requested-With": "fetch",
        "Accept": "text/html"
      },
      signal: currentController.signal
    });

    if (!response.ok) {
      throw new Error(`Navigation failed: ${response.status}`);
    }

    const html = await response.text();
    const doc = new DOMParser().parseFromString(html, "text/html");
    doc.documentElement.setAttribute("data-pwa-url", response.url);
    pageCache.set(cacheKey, doc);
    return doc.cloneNode(true);
  }

  async function navigateTo(href, options) {
    if (!appContent) {
      window.location.href = href;
      return;
    }

    const url = new URL(href, window.location.href);
    showSkeleton();

    try {
      const doc = await fetchPage(url);
      const finalUrl = new URL(doc.documentElement.getAttribute("data-pwa-url") || url.href, window.location.href);
      swapPage(doc, finalUrl, options && options.push);
    } catch (error) {
      if (error.name === "AbortError") return;
      window.location.href = url.href;
    }
  }

  function prefetchPage(href) {
    const url = new URL(href, window.location.href);
    const cacheKey = url.pathname + url.search;
    if (pageCache.has(cacheKey)) return;

    fetch(url.href, {
      headers: {
        "X-Requested-With": "prefetch",
        "Accept": "text/html"
      }
    })
      .then(function (response) {
        if (!response.ok) return null;
        return response.text();
      })
      .then(function (html) {
        if (!html) return;
        pageCache.set(cacheKey, new DOMParser().parseFromString(html, "text/html"));
      })
      .catch(function () {});
  }

  document.addEventListener("click", function (event) {
    const link = event.target instanceof Element ? event.target.closest("a") : null;
    if (!(link instanceof HTMLAnchorElement) || !isSameOriginPageLink(link)) return;

    event.preventDefault();
    navigateTo(link.href, { push: true });
  });

  document.addEventListener("click", function (event) {
    const button = event.target instanceof Element ? event.target.closest(".esarf-mobile-notes-btn") : null;
    if (!(button instanceof HTMLButtonElement)) return;

    const targetSelector = button.getAttribute("data-bs-target");
    const modalEl = targetSelector ? document.querySelector(targetSelector) : null;
    if (!modalEl || !window.bootstrap || typeof window.bootstrap.Modal !== "function") return;

    event.preventDefault();
    if (modalEl.parentElement !== document.body) {
      document.body.appendChild(modalEl);
    }

    window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
  });

  document.addEventListener("pointerover", function (event) {
    const link = event.target instanceof Element ? event.target.closest("a") : null;
    if (link instanceof HTMLAnchorElement && isSameOriginPageLink(link)) {
      prefetchPage(link.href);
    }
  }, { passive: true });

  window.addEventListener("popstate", function () {
    navigateTo(window.location.href, { push: false });
  });

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw.js").catch(function () {});
    });
  }
})();
