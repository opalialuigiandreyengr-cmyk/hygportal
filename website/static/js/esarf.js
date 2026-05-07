(function () {
  "use strict";

  const esarfForm = document.querySelector("form.esarf-grid");
  if (!esarfForm) return;

  const scheduleEl = esarfForm.querySelector('select[name="time_schedule"]');
  const dayOffEl = esarfForm.querySelector('select[name="day_off"]');
  const dateFromEl = esarfForm.querySelector('input[name="date_from"]');
  const dateToEl = esarfForm.querySelector('input[name="date_to"]');
  const timeFromEl = esarfForm.querySelector('input[name="time_from"]');
  const timeToEl = esarfForm.querySelector('input[name="time_to"]');
  const totalHoursEl = esarfForm.querySelector('input[name="total_hours"]');
  const otCheckbox = esarfForm.querySelector('input[name="transaction_type"][value="OT"]');
  const utCheckbox = esarfForm.querySelector('input[name="transaction_type"][value="UT"]');
  const offsetCheckbox = esarfForm.querySelector('input[name="transaction_type"][value="Offset"]');
  const useOffsetCheckbox = esarfForm.querySelector('input[name="transaction_type"][value="Use Offset"]');
  const offsetSummaryEl = esarfForm.querySelector("#offsetCreditSummary");
  const offsetAvailableEl = esarfForm.querySelector("#offsetAvailableHours");
  const offsetDeductEl = esarfForm.querySelector("#offsetDeductHours");
  const offsetRemainingEl = esarfForm.querySelector("#offsetRemainingHours");
  const transactionTypeEls = esarfForm.querySelectorAll('input[name="transaction_type"]');
  const transactionChecklistEl = esarfForm.querySelector(".transaction-checklist");
  const otAutoHintEl = esarfForm.querySelector("#otAutoHint");

  if (!scheduleEl || !dayOffEl || !dateFromEl || !dateToEl || !timeFromEl || !timeToEl || !totalHoursEl || !otCheckbox || !utCheckbox || !offsetCheckbox || !useOffsetCheckbox) return;

  const availableOffsetHours = offsetSummaryEl ? parseFloat(offsetSummaryEl.dataset.availableOffsetHours || "0") || 0 : 0;

  let manualTotalHoursValue = totalHoursEl.value || "";
  const formRequiredFieldEls = Array.from(
    esarfForm.querySelectorAll("input[required], select[required], textarea[required]")
  );
  const customRequiredFieldEls = [dateFromEl, dateToEl, timeFromEl, timeToEl];
  const requiredFieldEls = Array.from(new Set(formRequiredFieldEls.concat(customRequiredFieldEls)));

  function setMissingState(element, isMissing) {
    if (!element) return;
    element.classList.toggle("esarf-missing-field", Boolean(isMissing));
  }

  function clearCalculationFieldStates() {
    setMissingState(scheduleEl, false);
    setMissingState(dayOffEl, false);
    setMissingState(dateFromEl, false);
    setMissingState(timeFromEl, false);
    setMissingState(timeToEl, false);
  }

  function getAutoHintText(mode) {
    if (mode === "ot") {
      return "OT auto-calculated. If Date From matches Day Off, full worked hours are counted.";
    }
    if (mode === "offset") {
      return "Offset auto-calculated like OT. If Date From matches Day Off, full worked hours are counted.";
    }
    if (mode === "ut") {
      return "UT auto-calculated as the total hours/minutes not worked from the required schedule. If Date From matches Day Off, undertime is 0.";
    }
    if (mode === "use-offset") {
      return "Use Offset auto-calculated from your selected Time from and Time to.";
    }
    return "";
  }

  function setAutoHint(message, show) {
    if (!otAutoHintEl) return;
    otAutoHintEl.textContent = message || "";
    otAutoHintEl.classList.toggle("hidden", !show);
  }

  function clearAllValidationFeedback() {
    esarfForm.querySelectorAll(".esarf-missing-field").forEach(function (fieldEl) {
      fieldEl.classList.remove("esarf-missing-field");
    });
    setAutoHint("", false);
  }

  function getFocusTarget(fieldEl) {
    if (!fieldEl) return null;
    if (fieldEl.matches("input, select, textarea, button")) {
      return fieldEl;
    }
    return fieldEl.querySelector("input:not([type='hidden']), select, textarea, button");
  }

  function focusFirstProblemField() {
    const firstProblemField = esarfForm.querySelector(".esarf-missing-field");
    if (!firstProblemField) return;

    const focusTarget = getFocusTarget(firstProblemField) || firstProblemField;
    if (typeof focusTarget.scrollIntoView === "function") {
      focusTarget.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    if (typeof focusTarget.focus === "function") {
      window.setTimeout(function () {
        focusTarget.focus({ preventScroll: true });
      }, 120);
    }
  }

  function isFieldMissing(fieldEl) {
    if (!fieldEl) return true;
    const rawValue = fieldEl.value == null ? "" : String(fieldEl.value);
    return rawValue.trim() === "";
  }

  function validateRequiredFields() {
    let isValid = true;

    requiredFieldEls.forEach(function (fieldEl) {
      const missing = isFieldMissing(fieldEl);
      setMissingState(fieldEl, missing);
      if (missing) {
        isValid = false;
      }
    });

    return isValid;
  }

  function validateTransactionSelection() {
    const hasSelection = Array.from(transactionTypeEls).some(function (checkboxEl) {
      return checkboxEl.checked;
    });

    if (transactionChecklistEl) {
      setMissingState(transactionChecklistEl, !hasSelection);
    }

    return hasSelection;
  }

  function validateAutoCalculationState(mode) {
    if (mode !== "ot" && mode !== "ut" && mode !== "offset" && mode !== "use-offset") {
      updateBaseTotalHours();
    }

    calculateAutoHours();
    const hasValue = !isFieldMissing(totalHoursEl);
    setMissingState(totalHoursEl, !hasValue);
    return hasValue;
  }

  function validateFormBeforeSubmit() {
    const mode = getCalculationMode();
    const requiredOk = validateRequiredFields();
    const transactionOk = validateTransactionSelection();
    const calcOk = validateAutoCalculationState(mode);

    if (requiredOk && transactionOk && calcOk) {
      if (useOffsetCheckbox.checked) {
        const requestedHours = parseFloat(totalHoursEl.value || "0") || 0;
        if (requestedHours > availableOffsetHours) {
          setMissingState(totalHoursEl, true);
          setAutoHint("Requested hours exceed available offset credits.", true);
          focusFirstProblemField();
          return false;
        }
      }
      return true;
    }

    if (!transactionOk) {
      setAutoHint("Select at least one Transaction Type before submitting.", true);
      focusFirstProblemField();
      return false;
    }

    if (!calcOk && (mode === "ot" || mode === "ut" || mode === "offset" || mode === "use-offset")) {
      setAutoHint("Complete highlighted fields to auto-calculate " + mode.toUpperCase() + ".", true);
      focusFirstProblemField();
      return false;
    }

    setAutoHint("Please complete highlighted fields before submitting.", true);
    focusFirstProblemField();
    return false;
  }

  function parse12HourToken(token) {
    if (!token) return null;

    const cleaned = token.trim().toUpperCase().replace(/\s+/g, "");
    const match = cleaned.match(/^(\d{1,2})(?::(\d{2}))?(AM|PM)$/);
    if (!match) return null;

    let hours = parseInt(match[1], 10);
    const minutes = parseInt(match[2] || "0", 10);
    const meridiem = match[3];

    if (Number.isNaN(hours) || Number.isNaN(minutes) || minutes < 0 || minutes > 59 || hours < 1 || hours > 12) {
      return null;
    }

    if (hours === 12) {
      hours = 0;
    }

    if (meridiem === "PM") {
      hours += 12;
    }

    return hours * 60 + minutes;
  }

  function parseScheduleRange(scheduleText) {
    if (!scheduleText) return null;

    const parts = scheduleText.split("-");
    if (parts.length !== 2) return null;

    const scheduleStart = parse12HourToken(parts[0]);
    const scheduleEndBase = parse12HourToken(parts[1]);

    if (scheduleStart === null || scheduleEndBase === null) return null;

    let scheduleEnd = scheduleEndBase;
    if (scheduleEnd <= scheduleStart) {
      scheduleEnd += 24 * 60;
    }

    return { scheduleStart, scheduleEnd };
  }

  function parseTimeInput(value) {
    if (!value || !value.includes(":")) return null;
    const timeParts = value.split(":");
    if (timeParts.length !== 2) return null;

    const hours = parseInt(timeParts[0], 10);
    const minutes = parseInt(timeParts[1], 10);

    if (Number.isNaN(hours) || Number.isNaN(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      return null;
    }

    return hours * 60 + minutes;
  }

  function computeWorkedMinutes(workStartBase, workEndBase) {
    let workStart = workStartBase;
    let workEnd = workEndBase;

    if (workEnd <= workStart) {
      workEnd += 24 * 60;
    }

    return Math.max(0, workEnd - workStart);
  }

  function alignWorkAndScheduleRanges(scheduleRange, workStartBase, workEndBase) {
    let workStart = workStartBase;
    let workEnd = workEndBase;

    if (workEnd <= workStart) {
      workEnd += 24 * 60;
    }

    let scheduleStart = scheduleRange.scheduleStart;
    let scheduleEnd = scheduleRange.scheduleEnd;

    if (workStart >= scheduleEnd) {
      scheduleStart += 24 * 60;
      scheduleEnd += 24 * 60;
    } else if (workEnd <= scheduleStart) {
      workStart += 24 * 60;
      workEnd += 24 * 60;
    }

    return { workStart, workEnd, scheduleStart, scheduleEnd };
  }

  function normalizeDayOffValue(value) {
    const dayMap = {
      MON: "Mon",
      MONDAY: "Mon",
      TUE: "Tue",
      TUESDAY: "Tue",
      WED: "Wed",
      WEDNESDAY: "Wed",
      THU: "Thu",
      THURSDAY: "Thu",
      FRI: "Fri",
      FRIDAY: "Fri",
      SAT: "Sat",
      SATURDAY: "Sat",
      SUN: "Sun",
      SUNDAY: "Sun"
    };

    const normalized = (value || "").trim().toUpperCase();
    return dayMap[normalized] || null;
  }

  function getDayCodeFromDate(dateValue) {
    if (!dateValue) return null;

    const dateParts = dateValue.split("-");
    if (dateParts.length !== 3) return null;

    const year = parseInt(dateParts[0], 10);
    const monthIndex = parseInt(dateParts[1], 10) - 1;
    const day = parseInt(dateParts[2], 10);
    if (Number.isNaN(year) || Number.isNaN(monthIndex) || Number.isNaN(day)) return null;

    const dateObj = new Date(year, monthIndex, day);
    if (Number.isNaN(dateObj.getTime())) return null;

    const dayCodes = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    return dayCodes[dateObj.getDay()];
  }

  function isDayOffDate() {
    const selectedDayOff = normalizeDayOffValue(dayOffEl.value);
    const selectedDateDay = getDayCodeFromDate(dateFromEl.value);

    return Boolean(selectedDayOff && selectedDateDay && selectedDayOff === selectedDateDay);
  }

  function computeOvertimeMinutes(scheduleRange, workStartBase, workEndBase) {
    const ranges = alignWorkAndScheduleRanges(scheduleRange, workStartBase, workEndBase);
    const workStart = ranges.workStart;
    const workEnd = ranges.workEnd;
    const adjustedScheduleStart = ranges.scheduleStart;
    const adjustedScheduleEnd = ranges.scheduleEnd;

    const workDuration = workEnd - workStart;
    if (workDuration <= 0) return 0;

    const overlapStart = Math.max(workStart, adjustedScheduleStart);
    const overlapEnd = Math.min(workEnd, adjustedScheduleEnd);
    const scheduledOverlap = Math.max(0, overlapEnd - overlapStart);

    return Math.max(0, workDuration - scheduledOverlap);
  }

  function computeUndertimeMinutes(scheduleRange, workStartBase, workEndBase) {
    const ranges = alignWorkAndScheduleRanges(scheduleRange, workStartBase, workEndBase);
    const workStart = ranges.workStart;
    const workEnd = ranges.workEnd;
    const adjustedScheduleStart = ranges.scheduleStart;
    const adjustedScheduleEnd = ranges.scheduleEnd;

    const scheduleDuration = Math.max(0, adjustedScheduleEnd - adjustedScheduleStart);
    if (scheduleDuration <= 0) return 0;

    const overlapStart = Math.max(workStart, adjustedScheduleStart);
    const overlapEnd = Math.min(workEnd, adjustedScheduleEnd);
    const workedWithinSchedule = Math.max(0, overlapEnd - overlapStart);

    return Math.max(0, scheduleDuration - workedWithinSchedule);
  }

  function getCalculationMode() {
    const isOtSelected = otCheckbox.checked;
    const isUtSelected = utCheckbox.checked;
    const isOffsetSelected = offsetCheckbox.checked;
    const isUseOffsetSelected = useOffsetCheckbox.checked;

    if (isUseOffsetSelected) return "use-offset";
    if (isOffsetSelected) return "offset";
    if (isOtSelected && isUtSelected) return "mixed";
    if (isOtSelected) return "ot";
    if (isUtSelected) return "ut";
    return "none";
  }

  function enforceOffsetExclusivity() {
    const isOffsetSelected = offsetCheckbox.checked;
    const isUseOffsetSelected = useOffsetCheckbox.checked;

    if (!isOffsetSelected && !isUseOffsetSelected) {
      otCheckbox.disabled = false;
      utCheckbox.disabled = false;
      offsetCheckbox.disabled = false;
      useOffsetCheckbox.disabled = false;
      return;
    }

    // Offset and Use Offset are exclusive against OT/UT and each other.
    if (isOffsetSelected) {
      otCheckbox.checked = false;
      utCheckbox.checked = false;
      useOffsetCheckbox.checked = false;
      otCheckbox.disabled = true;
      utCheckbox.disabled = true;
      useOffsetCheckbox.disabled = true;
      offsetCheckbox.disabled = false;
      setAutoHint("Offset selected: OT and UT are disabled. Total hours will be saved as offset hours.", true);
      return;
    }

    if (isUseOffsetSelected) {
      otCheckbox.checked = false;
      utCheckbox.checked = false;
      offsetCheckbox.checked = false;
      otCheckbox.disabled = true;
      utCheckbox.disabled = true;
      offsetCheckbox.disabled = true;
      useOffsetCheckbox.disabled = false;
      setAutoHint("Use Offset selected: OT, UT, and Offset are disabled. Requested hours will deduct from your offset credits.", true);
    }
  }

  function updateOffsetSummary() {
    if (!offsetSummaryEl || !offsetAvailableEl || !offsetDeductEl || !offsetRemainingEl) return;

    const requestedHours = parseFloat(totalHoursEl.value || "0") || 0;
    const shouldDeduct = useOffsetCheckbox.checked;
    const deductHours = shouldDeduct ? requestedHours : 0;
    const remainingHours = availableOffsetHours - deductHours;

    offsetAvailableEl.textContent = availableOffsetHours.toFixed(2) + " hrs";
    offsetDeductEl.textContent = deductHours.toFixed(2) + " hrs";
    offsetRemainingEl.textContent = Math.max(0, remainingHours).toFixed(2) + " hrs";

    offsetSummaryEl.classList.toggle("is-error", shouldDeduct && requestedHours > availableOffsetHours);
    offsetSummaryEl.classList.toggle("hidden", !shouldDeduct);
  }

  function updateBaseTotalHours() {
    const workStart = parseTimeInput(timeFromEl.value);
    const workEnd = parseTimeInput(timeToEl.value);

    if (workStart === null || workEnd === null) {
      totalHoursEl.value = "";
      return;
    }

    const workedMinutes = computeWorkedMinutes(workStart, workEnd);
    if (workedMinutes <= 0) {
      totalHoursEl.value = "";
      return;
    }

    totalHoursEl.value = (workedMinutes / 60).toFixed(2);
  }

  function calculateAutoHours() {
    const mode = getCalculationMode();
    if (mode !== "ot" && mode !== "ut" && mode !== "offset" && mode !== "use-offset") return;

    if (mode === "use-offset") {
      const workStart = parseTimeInput(timeFromEl.value);
      const workEnd = parseTimeInput(timeToEl.value);
      if (workStart === null || workEnd === null) {
        totalHoursEl.value = "";
        setAutoHint("Complete Time from and Time to to auto-calculate USE-OFFSET.", true);
        updateOffsetSummary();
        return;
      }

      const workedMinutes = computeWorkedMinutes(workStart, workEnd);
      if (workedMinutes <= 0) {
        totalHoursEl.value = "";
        setAutoHint("Time To must be later than Time From for auto-calculation.", true);
        updateOffsetSummary();
        return;
      }

      totalHoursEl.value = (workedMinutes / 60).toFixed(2);
      setAutoHint(getAutoHintText(mode), true);
      updateOffsetSummary();
      return;
    }

    clearCalculationFieldStates();

    let hasMissingDependency = false;
    const scheduleRange = parseScheduleRange(scheduleEl.value);

    if (!scheduleEl.value || !scheduleRange) {
      setMissingState(scheduleEl, true);
      hasMissingDependency = true;
    }
    if (!dayOffEl.value) {
      setMissingState(dayOffEl, true);
      hasMissingDependency = true;
    }
    if (!dateFromEl.value) {
      setMissingState(dateFromEl, true);
      hasMissingDependency = true;
    }

    const workStart = parseTimeInput(timeFromEl.value);
    const workEnd = parseTimeInput(timeToEl.value);
    if (workStart === null) {
      setMissingState(timeFromEl, true);
      hasMissingDependency = true;
    }
    if (workEnd === null) {
      setMissingState(timeToEl, true);
      hasMissingDependency = true;
    }

    if (hasMissingDependency) {
      totalHoursEl.value = "";
      const modeLabel = mode === "offset" ? "OFFSET" : mode.toUpperCase();
      setAutoHint("Complete highlighted fields to auto-calculate " + modeLabel + ".", true);
      return;
    }

    const workedMinutes = computeWorkedMinutes(workStart, workEnd);
    if (workedMinutes <= 0) {
      setMissingState(timeFromEl, true);
      setMissingState(timeToEl, true);
      totalHoursEl.value = "";
      setAutoHint("Time To must be later than Time From for auto-calculation.", true);
      return;
    }

    if (isDayOffDate()) {
      if (mode === "ot" || mode === "offset") {
        totalHoursEl.value = (workedMinutes / 60).toFixed(2);
      } else {
        totalHoursEl.value = "0.00";
      }
      setAutoHint(getAutoHintText(mode), true);
      return;
    }

    if (mode === "ot" || mode === "offset") {
      const otMinutes = computeOvertimeMinutes(scheduleRange, workStart, workEnd);
      totalHoursEl.value = (otMinutes / 60).toFixed(2);
      setAutoHint(getAutoHintText(mode), true);
      updateOffsetSummary();
      return;
    }

    const utMinutes = computeUndertimeMinutes(scheduleRange, workStart, workEnd);
    totalHoursEl.value = (utMinutes / 60).toFixed(2);
    setAutoHint(getAutoHintText(mode), true);
    updateOffsetSummary();
  }

  function applyCalculationMode() {
    const mode = getCalculationMode();
    const isAutoMode = mode === "ot" || mode === "ut" || mode === "offset" || mode === "use-offset";

    if (isAutoMode) {
      clearCalculationFieldStates();
      totalHoursEl.readOnly = true;
      totalHoursEl.classList.add("esarf-auto-field");
      totalHoursEl.placeholder = "Auto-calculated";
      setAutoHint(getAutoHintText(mode), true);
      calculateAutoHours();
      updateOffsetSummary();
      return;
    }

    if (mode === "mixed") {
      clearCalculationFieldStates();
      totalHoursEl.readOnly = false;
      totalHoursEl.classList.remove("esarf-auto-field");
      totalHoursEl.placeholder = "";
      updateBaseTotalHours();
      setAutoHint("Total hours are auto-saved from the selected time range.", true);
      updateOffsetSummary();
      return;
    }

    clearCalculationFieldStates();
    totalHoursEl.readOnly = false;
    totalHoursEl.classList.remove("esarf-auto-field");
    totalHoursEl.placeholder = "";
    setAutoHint("", false);

    updateBaseTotalHours();
    updateOffsetSummary();
  }

  totalHoursEl.addEventListener("input", function () {
    if (getCalculationMode() !== "ot" && getCalculationMode() !== "ut" && getCalculationMode() !== "offset" && getCalculationMode() !== "use-offset") {
      manualTotalHoursValue = totalHoursEl.value;
    }
    if (!isFieldMissing(totalHoursEl)) {
      setMissingState(totalHoursEl, false);
    }
    updateOffsetSummary();
  });

  requiredFieldEls.forEach(function (fieldEl) {
    fieldEl.addEventListener("input", function () {
      if (!isFieldMissing(fieldEl)) {
        setMissingState(fieldEl, false);
      }
    });

    fieldEl.addEventListener("change", function () {
      if (!isFieldMissing(fieldEl)) {
        setMissingState(fieldEl, false);
      }
    });
  });

  scheduleEl.addEventListener("change", applyCalculationMode);
  dayOffEl.addEventListener("change", applyCalculationMode);
  dateFromEl.addEventListener("change", applyCalculationMode);
  timeFromEl.addEventListener("input", applyCalculationMode);
  timeToEl.addEventListener("input", applyCalculationMode);

  transactionTypeEls.forEach(function (checkbox) {
    checkbox.addEventListener("change", function () {
      enforceOffsetExclusivity();
      applyCalculationMode();
    });
    checkbox.addEventListener("change", function () {
      validateTransactionSelection();
      updateOffsetSummary();
    });
  });

  esarfForm.addEventListener("submit", function (event) {
    const isValid = validateFormBeforeSubmit();
    if (!isValid) {
      event.preventDefault();
    }
  });

  document.addEventListener("click", function (event) {
    if (!esarfForm.contains(event.target)) {
      clearAllValidationFeedback();
    }
  });

  enforceOffsetExclusivity();
  applyCalculationMode();
  updateOffsetSummary();
})();
