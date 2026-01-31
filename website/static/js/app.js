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

  window.addEventListener("resize", function () {
    if (window.innerWidth > 860) {
      setSidebarOpen(false);
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
  const confirmModalMsg = document.getElementById("globalConfirmModalMessage");
  const confirmModalSubmit = document.getElementById("globalConfirmModalSubmit");
  const confirmReasonWrap = document.getElementById("globalConfirmReasonWrap");
  const confirmReasonLabel = document.getElementById("globalConfirmReasonLabel");
  const confirmReasonInput = document.getElementById("globalConfirmReasonInput");
  const confirmReasonError = document.getElementById("globalConfirmReasonError");
  let pendingConfirmForm = null;
  let confirmModal = null;

  if (confirmModalEl && window.bootstrap && typeof window.bootstrap.Modal === "function") {
    confirmModal = new window.bootstrap.Modal(confirmModalEl);
  }

  function buildConfirmMessage(form) {
    const defaultMessage = "Are you sure you want to continue?";
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

    return staticMessage || defaultMessage;
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

    pendingConfirmForm = form;
    confirmModalMsg.textContent = buildConfirmMessage(form);
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
  });

  if (confirmModalEl) {
    confirmModalEl.addEventListener("hidden.bs.modal", function () {
      pendingConfirmForm = null;
      resetConfirmReasonUi();
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
})();
