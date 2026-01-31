function previewCompanyLogo(event, previewId) {
  const target = document.getElementById(previewId);
  const file = event.target.files && event.target.files[0];
  if (!target || !file) return;

  const reader = new FileReader();
  reader.onload = function () {
    target.innerHTML =
      '<img src="' +
      reader.result +
      '" alt="Company Logo Preview" class="company-logo-preview">';
  };
  reader.readAsDataURL(file);
}
