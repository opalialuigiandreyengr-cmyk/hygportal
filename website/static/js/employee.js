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
  addEmployeeForm.addEventListener("submit", function (event) {
    const photoInput = document.getElementById("photoUploadAdd");
    if (!photoInput || !photoInput.files || photoInput.files.length === 0) {
      event.preventDefault();
      setPhotoError("Add", "Please attach an ID photo before saving employee.");
      return;
    }
    if (!isAllowedImageFile(photoInput.files[0])) {
      event.preventDefault();
      setPhotoError("Add", "Only JPG and PNG image formats are allowed.");
      return;
    }
    setPhotoError("Add", "");
  });
}
