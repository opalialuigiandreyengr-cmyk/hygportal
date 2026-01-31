(function () {
  "use strict";

  function mapTone(type) {
    const toneMap = {
      success: "success",
      error: "danger",
      danger: "danger",
      warning: "warning",
      info: "info"
    };
    return toneMap[type] || "secondary";
  }

  function toneMeta(tone) {
    const meta = {
      success: { title: "Success", icon: "fa-circle-check" },
      danger: { title: "Error", icon: "fa-circle-xmark" },
      warning: { title: "Warning", icon: "fa-triangle-exclamation" },
      info: { title: "Info", icon: "fa-circle-info" },
      secondary: { title: "Notice", icon: "fa-bell" }
    };
    return meta[tone] || meta.secondary;
  }

  function ensureDynamicContainer() {
    let container = document.querySelector(".toast-container.dynamic-toast");
    if (container) return container;

    container = document.createElement("div");
    container.className = "toast-container dynamic-toast position-fixed top-0 end-0 p-3";
    container.style.zIndex = "1200";
    document.body.appendChild(container);
    return container;
  }

  function show(type, message, delay) {
    if (!window.bootstrap || !bootstrap.Toast) return;

    const tone = mapTone(type);
    const meta = toneMeta(tone);
    const toastEl = document.createElement("div");

    toastEl.className = "toast hyg-toast border-0 mb-2";
    toastEl.setAttribute("role", "alert");
    toastEl.setAttribute("aria-live", "assertive");
    toastEl.setAttribute("aria-atomic", "true");
    toastEl.setAttribute("data-bs-delay", String(delay || 3500));
    toastEl.setAttribute("data-tone", tone);
    toastEl.innerHTML =
      '<div class="toast-content">' +
      '<div class="toast-icon" aria-hidden="true"><i class="fa-solid ' + meta.icon + '"></i></div>' +
      '<div class="toast-copy">' +
      '<div class="toast-title">' + meta.title + "</div>" +
      '<div class="toast-body"></div>' +
      "</div>" +
      '<button type="button" class="btn-close ms-2" data-bs-dismiss="toast" aria-label="Close"></button>' +
      "</div>";

    const bodyEl = toastEl.querySelector(".toast-body");
    if (bodyEl) bodyEl.textContent = message || "";

    ensureDynamicContainer().appendChild(toastEl);
    const instance = bootstrap.Toast.getOrCreateInstance(toastEl);
    instance.show();
    toastEl.addEventListener("hidden.bs.toast", function () {
      toastEl.remove();
    });
  }

  function showExisting() {
    if (!window.bootstrap || !bootstrap.Toast) return;
    document.querySelectorAll(".toast").forEach(function (toastEl) {
      bootstrap.Toast.getOrCreateInstance(toastEl).show();
    });
  }

  window.HYGToast = {
    show: show,
    showExisting: showExisting
  };

  window.addEventListener("DOMContentLoaded", showExisting);
})();
