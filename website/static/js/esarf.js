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
  const transactionTypeEls = esarfForm.querySelectorAll('input[name="transaction_type"]');
  const transactionChecklistEl = esarfForm.querySelector(".transaction-checklist");
  const otAutoHintEl = esarfForm.querySelector("#otAutoHint");

  if (!scheduleEl || !dayOffEl || !dateFromEl || !dateToEl || !timeFromEl || !timeToEl || !totalHoursEl || !otCheckbox || !utCheckbox) return;

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
    if (mode === "ut") {
      return "UT auto-calculated as the total hours/minutes not worked from the required schedule. If Date From matches Day Off, undertime is 0.";
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
    if (mode !== "ot" && mode !== "ut") {
      return true;
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
      return true;
    }

    if (!transactionOk) {
      setAutoHint("Select at least one Transaction Type before submitting.", true);
      focusFirstProblemField();
      return false;
    }

    if (!calcOk && (mode === "ot" || mode === "ut")) {
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

    if (isOtSelected && isUtSelected) return "mixed";
    if (isOtSelected) return "ot";
    if (isUtSelected) return "ut";
    return "none";
  }

  function calculateAutoHours() {
    const mode = getCalculationMode();
    if (mode !== "ot" && mode !== "ut") return;

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
      setAutoHint("Complete highlighted fields to auto-calculate " + mode.toUpperCase() + ".", true);
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
      if (mode === "ot") {
        totalHoursEl.value = (workedMinutes / 60).toFixed(2);
      } else {
        totalHoursEl.value = "0.00";
      }
      setAutoHint(getAutoHintText(mode), true);
      return;
    }

    if (mode === "ot") {
      const otMinutes = computeOvertimeMinutes(scheduleRange, workStart, workEnd);
      totalHoursEl.value = (otMinutes / 60).toFixed(2);
      setAutoHint(getAutoHintText(mode), true);
      return;
    }

    const utMinutes = computeUndertimeMinutes(scheduleRange, workStart, workEnd);
    totalHoursEl.value = (utMinutes / 60).toFixed(2);
    setAutoHint(getAutoHintText(mode), true);
  }

  function applyCalculationMode() {
    const mode = getCalculationMode();
    const isAutoMode = mode === "ot" || mode === "ut";

    if (isAutoMode) {
      clearCalculationFieldStates();
      totalHoursEl.readOnly = true;
      totalHoursEl.classList.add("esarf-auto-field");
      totalHoursEl.placeholder = "Auto-calculated";
      setAutoHint(getAutoHintText(mode), true);
      calculateAutoHours();
      return;
    }

    if (mode === "mixed") {
      clearCalculationFieldStates();
      totalHoursEl.readOnly = false;
      totalHoursEl.classList.remove("esarf-auto-field");
      totalHoursEl.placeholder = "";
      setAutoHint("OT and UT both selected. Enter total hours manually.", true);
      return;
    }

    clearCalculationFieldStates();
    totalHoursEl.readOnly = false;
    totalHoursEl.classList.remove("esarf-auto-field");
    totalHoursEl.placeholder = "";
    setAutoHint("", false);

    if (!totalHoursEl.value && manualTotalHoursValue) {
      totalHoursEl.value = manualTotalHoursValue;
    }
  }

  totalHoursEl.addEventListener("input", function () {
    if (getCalculationMode() !== "ot" && getCalculationMode() !== "ut") {
      manualTotalHoursValue = totalHoursEl.value;
    }
    if (!isFieldMissing(totalHoursEl)) {
      setMissingState(totalHoursEl, false);
    }
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

  scheduleEl.addEventListener("change", calculateAutoHours);
  dayOffEl.addEventListener("change", calculateAutoHours);
  dateFromEl.addEventListener("change", calculateAutoHours);
  timeFromEl.addEventListener("input", calculateAutoHours);
  timeToEl.addEventListener("input", calculateAutoHours);

  transactionTypeEls.forEach(function (checkbox) {
    checkbox.addEventListener("change", applyCalculationMode);
    checkbox.addEventListener("change", function () {
      validateTransactionSelection();
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

  applyCalculationMode();
})();
