function isAllowedImageFile(file) {
  if (!file) return false;
  const allowedTypes = ["image/jpeg", "image/png"];
  const fileName = (file.name || "").toLowerCase();
  const hasAllowedExtension =
    fileName.endsWith(".jpg") ||
    fileName.endsWith(".jpeg") ||
    fileName.endsWith(".png");
  return allowedTypes.includes(file.type) || hasAllowedExtension;
}

function scrollAddEmployeeModalToTop() {
  const addModal = document.getElementById("addEmployeeModal");
  const modalBody = addModal ? addModal.querySelector(".modal-body") : null;

  if (modalBody) {
    modalBody.scrollTo({ top: 0, behavior: "smooth" });
    return;
  }

  window.scrollTo({ top: 0, behavior: "smooth" });
}

function setPhotoError(id, message) {
  const errorEl = document.getElementById("photoUpload" + id + "Error");
  const previewDiv = document.getElementById("photoPreview" + id);

  if (!errorEl || !previewDiv) return;

  if (message) {
    errorEl.textContent = message;
    errorEl.classList.remove("hidden");
    previewDiv.classList.add("error-state");
    if (id === "Add") {
      scrollAddEmployeeModalToTop();
    }
    return;
  }

  errorEl.classList.add("hidden");
  previewDiv.classList.remove("error-state");
}

function previewImage(event, id) {
  const maxFileSize = 10 * 1024 * 1024;
  const file = event.target.files[0];
  if (!file) return;
  if (!isAllowedImageFile(file)) {
    const hasInlineError = document.getElementById("photoUpload" + id + "Error");
    if (hasInlineError) {
      setPhotoError(id, "Only JPG and PNG image formats are allowed.");
    } else {
      alert("Only JPG and PNG image formats are allowed.");
    }
    event.target.value = "";
    return;
  }
  if (file.size > maxFileSize) {
    const hasInlineError = document.getElementById("photoUpload" + id + "Error");
    if (hasInlineError) {
      setPhotoError(id, "ID picture must be 10MB or smaller.");
    } else {
      alert("ID picture must be 10MB or smaller.");
    }
    event.target.value = "";
    return;
  }
  const reader = new FileReader();
  reader.onload = function () {
    const previewDiv = document.getElementById("photoPreview" + id);
    previewDiv.innerHTML =
      '<img src="' +
      reader.result +
      '" alt="Profile Preview" style="width:100%;height:100%;object-fit:contain;border-radius:6px;background:#fff;padding:6px;">';
    setPhotoError(id, "");
  };
  reader.readAsDataURL(file);
}

const addEmployeeForm = document.getElementById("addEmployeeForm");
if (addEmployeeForm) {
  const birthDateInput = addEmployeeForm.querySelector('input[name="birth_date"]');
  const ageInput = addEmployeeForm.querySelector('input[name="age"]');

  const computeAgeFromBirthDate = (birthDateValue) => {
    if (!birthDateValue) return "";

    const birthDate = new Date(birthDateValue + "T00:00:00");
    if (Number.isNaN(birthDate.getTime())) return "";

    const today = new Date();
    let age = today.getFullYear() - birthDate.getFullYear();
    const monthDiff = today.getMonth() - birthDate.getMonth();
    const dayDiff = today.getDate() - birthDate.getDate();

    if (monthDiff < 0 || (monthDiff === 0 && dayDiff < 0)) {
      age -= 1;
    }

    if (age < 0) return "";
    return String(age);
  };

  if (birthDateInput && ageInput) {
    const syncAge = () => {
      ageInput.value = computeAgeFromBirthDate(birthDateInput.value);
    };
    birthDateInput.addEventListener("change", syncAge);
    birthDateInput.addEventListener("input", syncAge);
    syncAge();
  }

  addEmployeeForm.addEventListener("submit", function (event) {
    const photoInput = document.getElementById("photoUploadAdd");
    if (photoInput && photoInput.files && photoInput.files.length > 0 && !isAllowedImageFile(photoInput.files[0])) {
      event.preventDefault();
      setPhotoError("Add", "Only JPG and PNG image formats are allowed.");
      return;
    }
    setPhotoError("Add", "");
  });
}

function initEditEmployeeMissingDataHighlights() {
  const editModals = document.querySelectorAll('[id^="editEmployeeModal"]');
  if (!editModals.length) return;

  const isEmptyField = (field) => {
    if (!field) return false;
    const tag = field.tagName;
    const type = (field.getAttribute("type") || "").toLowerCase();

    if (type === "hidden" || type === "file" || type === "submit" || type === "button") {
      return false;
    }

    if (tag === "SELECT") {
      return !(field.value || "").trim();
    }

    return !(field.value || "").trim();
  };

  const updateFieldState = (field) => {
    const isMissing = isEmptyField(field);
    field.classList.toggle("missing-data-highlight", isMissing);

    const container = field.closest(".field");
    if (container) {
      container.classList.toggle("missing-data-field", isMissing);
    }

    const tag = field.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA") {
      if (!field.dataset.originalPlaceholder) {
        field.dataset.originalPlaceholder = field.getAttribute("placeholder") || "";
      }
      field.setAttribute("placeholder", isMissing ? "No data" : field.dataset.originalPlaceholder);
    }
  };

  editModals.forEach((modal) => {
    const form = modal.querySelector(".employee-form");
    if (!form) return;

    const fields = form.querySelectorAll("input, select, textarea");
    fields.forEach((field) => {
      field.addEventListener("input", () => updateFieldState(field));
      field.addEventListener("change", () => updateFieldState(field));
    });

    modal.addEventListener("shown.bs.modal", () => {
      fields.forEach((field) => updateFieldState(field));
    });
  });
}

initEditEmployeeMissingDataHighlights();
