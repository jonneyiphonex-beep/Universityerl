"use strict";

const STORAGE_KEY = "universityerl.demo.structure.v1";

const UNIT_TYPES = {
  region: { label: "منطقة", plural: "المناطق", symbol: "◎", parent: null },
  campus: { label: "فرع", plural: "الفروع", symbol: "⌂", parent: "region" },
  college: { label: "كلية", plural: "الكليات", symbol: "▦", parent: "campus" },
  department: { label: "قسم", plural: "الأقسام", symbol: "⌘", parent: "college" },
  program: { label: "برنامج", plural: "البرامج", symbol: "▤", parent: "department" },
};

const seedUnits = [
  { id: "reg-central", type: "region", code: "CTR", name: "المنطقة الوسطى", parentId: null, status: "active", createdAt: "2026-08-11T08:00:00.000Z" },
  { id: "reg-west", type: "region", code: "WST", name: "المنطقة الغربية", parentId: null, status: "active", createdAt: "2026-08-10T08:00:00.000Z" },
  { id: "reg-north", type: "region", code: "NTH", name: "المنطقة الشمالية", parentId: null, status: "active", createdAt: "2026-08-09T08:00:00.000Z" },
  { id: "cam-riyadh", type: "campus", code: "RUH", name: "فرع الرياض", parentId: "reg-central", status: "active", createdAt: "2026-08-08T08:00:00.000Z" },
  { id: "cam-kharj", type: "campus", code: "KHR", name: "فرع الخرج", parentId: "reg-central", status: "active", createdAt: "2026-08-07T08:00:00.000Z" },
  { id: "cam-jeddah", type: "campus", code: "JED", name: "فرع جدة", parentId: "reg-west", status: "active", createdAt: "2026-08-06T08:00:00.000Z" },
  { id: "cam-tabuk", type: "campus", code: "TBU", name: "فرع تبوك", parentId: "reg-north", status: "inactive", createdAt: "2026-08-05T08:00:00.000Z" },
  { id: "col-eng", type: "college", code: "ENG", name: "كلية الهندسة", parentId: "cam-riyadh", status: "active", createdAt: "2026-08-04T08:00:00.000Z" },
  { id: "col-computing", type: "college", code: "CCS", name: "كلية الحوسبة", parentId: "cam-riyadh", status: "active", createdAt: "2026-08-03T08:00:00.000Z" },
  { id: "col-medicine", type: "college", code: "MED", name: "كلية الطب", parentId: "cam-jeddah", status: "active", createdAt: "2026-08-02T08:00:00.000Z" },
  { id: "dep-cs", type: "department", code: "CS", name: "علوم الحاسب", parentId: "col-computing", status: "active", createdAt: "2026-08-01T08:00:00.000Z" },
  { id: "dep-cyber", type: "department", code: "CYB", name: "الأمن السيبراني", parentId: "col-computing", status: "active", createdAt: "2026-07-30T08:00:00.000Z" },
  { id: "dep-civil", type: "department", code: "CIV", name: "الهندسة المدنية", parentId: "col-eng", status: "active", createdAt: "2026-07-29T08:00:00.000Z" },
  { id: "dep-surgery", type: "department", code: "SUR", name: "الجراحة", parentId: "col-medicine", status: "active", createdAt: "2026-07-28T08:00:00.000Z" },
  { id: "prg-software", type: "program", code: "SE-BS", name: "بكالوريوس هندسة البرمجيات", parentId: "dep-cs", status: "active", createdAt: "2026-07-27T08:00:00.000Z" },
  { id: "prg-cyber", type: "program", code: "CY-BS", name: "بكالوريوس الأمن السيبراني", parentId: "dep-cyber", status: "active", createdAt: "2026-07-26T08:00:00.000Z" },
  { id: "prg-civil", type: "program", code: "CE-BS", name: "بكالوريوس الهندسة المدنية", parentId: "dep-civil", status: "inactive", createdAt: "2026-07-25T08:00:00.000Z" },
];

const seedActivity = [
  { action: "تحديث تجريبي", name: "فرع الرياض", detail: "المنطقة الوسطى", createdAt: "2026-08-11T08:00:00.000Z" },
  { action: "إضافة تجريبية", name: "بكالوريوس هندسة البرمجيات", detail: "علوم الحاسب", createdAt: "2026-08-09T08:00:00.000Z" },
  { action: "إضافة تجريبية", name: "كلية الطب", detail: "فرع جدة", createdAt: "2026-08-07T08:00:00.000Z" },
];

function loadState() {
  try {
    const stored = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (stored && Array.isArray(stored.units) && Array.isArray(stored.activity)) return stored;
  } catch (error) {
    console.warn("تعذر قراءة البيانات المحلية؛ سيتم تحميل البيانات التجريبية.", error);
  }
  return { units: structuredClone(seedUnits), activity: structuredClone(seedActivity) };
}

let state = loadState();
let toastTimer;
let monitorRequestId = 0;

const elements = {
  overview: document.getElementById("overview-view"),
  unitsView: document.getElementById("units-view"),
  monitorView: document.getElementById("monitor-view"),
  navLinks: [...document.querySelectorAll("[data-view]")],
  pageLabel: document.getElementById("current-page-label"),
  unitTable: document.getElementById("units-table-body"),
  recentTable: document.getElementById("recent-table-body"),
  metrics: document.getElementById("metrics-grid"),
  distribution: document.getElementById("distribution-list"),
  activity: document.getElementById("activity-list"),
  search: document.getElementById("unit-search"),
  filter: document.getElementById("type-filter"),
  resultsCount: document.getElementById("results-count"),
  emptyState: document.getElementById("empty-state"),
  dialog: document.getElementById("unit-dialog"),
  form: document.getElementById("unit-form"),
  toast: document.getElementById("toast"),
};

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (error) {
    showToast("تعذر حفظ البيانات في هذا المتصفح.");
    console.error("تعذر حفظ بيانات الواجهة التجريبية.", error);
  }
}

function getParent(unit) {
  return state.units.find((candidate) => candidate.id === unit.parentId);
}

function sortedUnits(units = state.units) {
  return [...units].sort((a, b) => a.name.localeCompare(b.name, "ar"));
}

function formatDate(dateString) {
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return "الآن";
  return new Intl.DateTimeFormat("ar", { day: "numeric", month: "short" }).format(date);
}

function unitIdentityMarkup(unit) {
  const typeInfo = UNIT_TYPES[unit.type];
  return `<span class="unit-name-cell"><span class="unit-symbol type-${unit.type}" aria-hidden="true">${typeInfo.symbol}</span><span>${escapeHTML(unit.name)}</span></span>`;
}

function statusMarkup(status) {
  const inactive = status === "inactive";
  return `<span class="status-pill${inactive ? " is-inactive" : ""}">${inactive ? "غير نشطة" : "نشطة"}</span>`;
}

function renderMetrics() {
  const count = (type) => state.units.filter((unit) => unit.type === type).length;
  const active = state.units.filter((unit) => unit.status === "active").length;
  const metrics = [
    { label: "إجمالي الوحدات", value: state.units.length, symbol: "⌘", note: "في جميع المناطق" },
    { label: "المناطق", value: count("region"), symbol: "◎", note: "نطاقات إدارية" },
    { label: "الكليات والأقسام", value: count("college") + count("department"), symbol: "▦", note: "وحدات أكاديمية" },
    { label: "البرامج النشطة", value: state.units.filter((unit) => unit.type === "program" && unit.status === "active").length, symbol: "▤", note: `${active} وحدة نشطة إجمالًا` },
  ];
  elements.metrics.innerHTML = metrics.map((metric) => `
    <article class="metric">
      <div class="metric-label"><span>${metric.label}</span><span class="metric-glyph" aria-hidden="true">${metric.symbol}</span></div>
      <strong class="metric-value">${metric.value}<span class="metric-note">${metric.note}</span></strong>
    </article>`).join("");
  document.getElementById("banner-unit-count").textContent = String(state.units.length).padStart(2, "0");
  document.getElementById("nav-unit-count").textContent = state.units.length;
}

function renderDistribution() {
  const max = Math.max(1, ...Object.keys(UNIT_TYPES).map((type) => state.units.filter((unit) => unit.type === type).length));
  elements.distribution.innerHTML = Object.entries(UNIT_TYPES).map(([type, info]) => {
    const count = state.units.filter((unit) => unit.type === type).length;
    return `<div class="distribution-row">
      <span class="distribution-label">${info.plural}</span>
      <span class="distribution-track"><span class="distribution-fill" style="width:${Math.max(count ? 7 : 0, count / max * 100)}%"></span></span>
      <span class="distribution-count">${count}</span>
    </div>`;
  }).join("");
}

function renderActivity() {
  const activity = [...state.activity].slice(0, 5);
  elements.activity.innerHTML = activity.length ? activity.map((item) => `
    <div class="activity-item">
      <span class="activity-mark" aria-hidden="true">↻</span>
      <span class="activity-copy"><strong>${escapeHTML(item.action)} · ${escapeHTML(item.name)}</strong><small>${escapeHTML(item.detail || "الهيكل الأكاديمي")}</small></span>
      <time class="activity-time">${formatDate(item.createdAt)}</time>
    </div>`).join("") : '<p class="activity-empty">لا توجد تغييرات مسجلة بعد.</p>';
}

function renderRecent() {
  const recent = [...state.units].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 5);
  elements.recentTable.innerHTML = recent.map((unit) => {
    const parent = getParent(unit);
    return `<tr>
      <td>${unitIdentityMarkup(unit)}</td>
      <td>${UNIT_TYPES[unit.type].label}</td>
      <td dir="ltr">${escapeHTML(unit.code)}</td>
      <td>${parent ? escapeHTML(parent.name) : "—"}</td>
      <td>${statusMarkup(unit.status)}</td>
    </tr>`;
  }).join("");
}

function renderUnits() {
  const query = elements.search.value.trim().toLocaleLowerCase("ar");
  const selectedType = elements.filter.value;
  const filtered = sortedUnits(state.units.filter((unit) => {
    const matchesQuery = !query || unit.name.toLocaleLowerCase("ar").includes(query) || unit.code.toLocaleLowerCase("ar").includes(query);
    return matchesQuery && (selectedType === "all" || unit.type === selectedType);
  }));
  elements.resultsCount.textContent = `${filtered.length} من ${state.units.length} وحدة`;
  elements.emptyState.hidden = filtered.length > 0;
  elements.unitTable.closest(".table-wrap").hidden = filtered.length === 0;
  elements.unitTable.innerHTML = filtered.map((unit) => {
    const parent = getParent(unit);
    return `<tr>
      <td>${unitIdentityMarkup(unit)}</td>
      <td>${UNIT_TYPES[unit.type].label}</td>
      <td dir="ltr">${escapeHTML(unit.code)}</td>
      <td>${parent ? escapeHTML(parent.name) : "—"}</td>
      <td>${statusMarkup(unit.status)}</td>
      <td><div class="row-actions">
        <button class="row-action" type="button" data-action="edit" data-id="${escapeHTML(unit.id)}" aria-label="تعديل ${escapeHTML(unit.name)}" title="تعديل">✎</button>
        <button class="row-action delete" type="button" data-action="delete" data-id="${escapeHTML(unit.id)}" aria-label="حذف ${escapeHTML(unit.name)}" title="حذف">×</button>
      </div></td>
    </tr>`;
  }).join("");
}

function renderAll() {
  renderMetrics();
  renderDistribution();
  renderActivity();
  renderRecent();
  renderUnits();
}

function setView(view) {
  const isUnits = view === "units";
  const isMonitor = view === "monitor";
  elements.overview.hidden = isUnits || isMonitor;
  elements.unitsView.hidden = !isUnits;
  elements.monitorView.hidden = !isMonitor;
  elements.overview.classList.toggle("is-visible", !isUnits && !isMonitor);
  elements.unitsView.classList.toggle("is-visible", isUnits);
  elements.monitorView.classList.toggle("is-visible", isMonitor);
  elements.pageLabel.textContent = isUnits ? "الهيكل الأكاديمي" : isMonitor ? "مراقبة الموارد" : "نظرة عامة";
  elements.navLinks.forEach((link) => {
    const active = link.dataset.view === view;
    link.classList.toggle("is-active", active);
    if (link.classList.contains("nav-link")) {
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
  });
  document.getElementById("sidebar").classList.remove("is-open");
  document.getElementById("mobile-menu").setAttribute("aria-expanded", "false");
  if (isMonitor) refreshMonitor();
}

function formatStorage(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) return "غير متاح";
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(0)} كيلوبايت`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} ميغابايت`;
  return `${(bytes / 1024 ** 3).toFixed(2)} غيغابايت`;
}

async function refreshMonitor() {
  const requestId = ++monitorRequestId;
  const cores = Number.isFinite(navigator.hardwareConcurrency) ? navigator.hardwareConcurrency : null;
  const memory = Number.isFinite(navigator.deviceMemory) ? navigator.deviceMemory : null;
  const connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection;

  document.getElementById("cpu-cores").textContent = cores ? String(cores) : "غير متاح";
  document.getElementById("memory-estimate").textContent = memory ? `نحو ${memory} غيغابايت` : "غير متاح";
  document.getElementById("network-speed").textContent = Number.isFinite(connection?.downlink) ? String(connection.downlink) : "غير متاح";
  document.getElementById("network-type").textContent = connection?.effectiveType || "غير متاح في هذا المتصفح";
  document.getElementById("network-status").textContent = navigator.onLine ? "متصل بالشبكة" : "غير متصل";
  document.getElementById("monitor-updated").textContent = new Intl.DateTimeFormat("ar", { hour: "numeric", minute: "2-digit" }).format(new Date());

  const usage = document.getElementById("storage-used");
  const quota = document.getElementById("storage-quota");
  const meter = document.getElementById("storage-meter");
  if (!navigator.storage?.estimate) {
    usage.textContent = "غير متاح";
    quota.textContent = "واجهة التخزين غير مدعومة";
    meter.style.width = "0%";
    return;
  }

  try {
    const estimate = await navigator.storage.estimate();
    if (requestId !== monitorRequestId) return;
    usage.textContent = formatStorage(estimate.usage);
    quota.textContent = formatStorage(estimate.quota);
    const percent = estimate.quota ? Math.min(100, (estimate.usage || 0) / estimate.quota * 100) : 0;
    meter.style.width = `${percent.toFixed(1)}%`;
  } catch (error) {
    if (requestId !== monitorRequestId) return;
    usage.textContent = "تعذر القياس";
    quota.textContent = "غير متاح";
    meter.style.width = "0%";
  }
}

function requiredParentType(type) {
  return UNIT_TYPES[type].parent;
}

function updateParentOptions(selectedId = "") {
  const type = document.getElementById("unit-type").value;
  const parentType = requiredParentType(type);
  const field = document.getElementById("parent-field");
  const select = document.getElementById("unit-parent");
  const hint = document.getElementById("parent-hint");
  const candidates = parentType ? sortedUnits(state.units.filter((unit) => unit.type === parentType && unit.status === "active")) : [];
  field.hidden = !parentType;
  select.required = Boolean(parentType);
  hint.textContent = parentType ? `اختر ${UNIT_TYPES[parentType].label} التي تتبع لها هذه الوحدة.` : "تُعد المنطقة أعلى مستوى في الهيكل.";
  select.innerHTML = candidates.map((unit) => `<option value="${escapeHTML(unit.id)}">${escapeHTML(unit.name)} (${escapeHTML(unit.code)})</option>`).join("");
  if (selectedId && candidates.some((unit) => unit.id === selectedId)) select.value = selectedId;
  if (parentType && candidates.length === 0) {
    select.innerHTML = "<option value=\"\">لا توجد وحدات أعلى نشطة</option>";
    select.disabled = true;
  } else {
    select.disabled = false;
  }
}

function openDialog(unit = null) {
  elements.form.reset();
  document.getElementById("form-error").hidden = true;
  document.getElementById("unit-id").value = unit?.id || "";
  document.getElementById("unit-type").disabled = Boolean(unit);
  document.getElementById("unit-type").value = unit?.type || "region";
  document.getElementById("unit-name").value = unit?.name || "";
  document.getElementById("unit-code").value = unit?.code || "";
  document.getElementById("unit-status").value = unit?.status || "active";
  document.getElementById("dialog-title").textContent = unit ? "تعديل وحدة" : "إضافة وحدة";
  updateParentOptions(unit?.parentId || "");
  elements.dialog.showModal();
  document.getElementById("unit-name").focus();
}

function closeDialog() {
  elements.dialog.close();
  document.getElementById("unit-type").disabled = false;
}

function showToast(message) {
  elements.toast.textContent = message;
  elements.toast.classList.add("is-visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => elements.toast.classList.remove("is-visible"), 2800);
}

function recordActivity(action, unit) {
  const parent = unit.parentId ? state.units.find((candidate) => candidate.id === unit.parentId) : null;
  state.activity.unshift({ action, name: unit.name, detail: parent?.name || "المنطقة", createdAt: new Date().toISOString() });
  state.activity = state.activity.slice(0, 20);
}

function saveUnit(event) {
  event.preventDefault();
  const id = document.getElementById("unit-id").value;
  const type = document.getElementById("unit-type").value;
  const name = document.getElementById("unit-name").value.trim();
  const code = document.getElementById("unit-code").value.trim().toUpperCase();
  const parentId = requiredParentType(type) ? document.getElementById("unit-parent").value : null;
  const status = document.getElementById("unit-status").value;
  const error = document.getElementById("form-error");
  const parentType = requiredParentType(type);

  if (!name || !code) {
    error.textContent = "أدخل اسم الوحدة ورمزها.";
    error.hidden = false;
    return;
  }
  if (parentType && !state.units.some((unit) => unit.id === parentId && unit.type === parentType && unit.status === "active")) {
    error.textContent = `أضف ${UNIT_TYPES[parentType].label} نشطة أولًا، ثم اربط الوحدة بها.`;
    error.hidden = false;
    return;
  }
  const duplicate = state.units.some((unit) => unit.id !== id && unit.type === type && unit.parentId === parentId && unit.code.toLocaleLowerCase("ar") === code.toLocaleLowerCase("ar"));
  if (duplicate) {
    error.textContent = "هذا الرمز مستخدم لوحدة من النوع نفسه ضمن الوحدة الأعلى ذاتها.";
    error.hidden = false;
    return;
  }

  const existing = state.units.find((unit) => unit.id === id);
  const unit = {
    id: existing?.id || (crypto.randomUUID ? crypto.randomUUID() : `unit-${Date.now()}-${Math.random().toString(16).slice(2)}`),
    type,
    name,
    code,
    parentId,
    status,
    createdAt: existing?.createdAt || new Date().toISOString(),
  };
  if (existing) state.units = state.units.map((candidate) => candidate.id === id ? unit : candidate);
  else state.units.push(unit);
  recordActivity(existing ? "تعديل" : "إضافة", unit);
  persist();
  renderAll();
  closeDialog();
  showToast(existing ? "تم تحديث الوحدة محليًا." : "تمت إضافة الوحدة محليًا.");
}

function deleteUnit(id) {
  const unit = state.units.find((candidate) => candidate.id === id);
  if (!unit) return;
  const children = state.units.filter((candidate) => candidate.parentId === id);
  if (children.length) {
    showToast(`لا يمكن الحذف؛ توجد ${children.length} وحدة تابعة. انقلها أو احذفها أولًا.`);
    return;
  }
  if (!window.confirm(`حذف «${unit.name}» من البيانات المحلية؟`)) return;
  state.units = state.units.filter((candidate) => candidate.id !== id);
  recordActivity("حذف", unit);
  persist();
  renderAll();
  showToast("تم حذف الوحدة من البيانات المحلية.");
}

function csvCell(value) {
  const text = String(value);
  const safeText = /^[\t\r\n ]*[=+\-@]/.test(text) ? `'${text}` : text;
  return `"${safeText.replace(/"/g, '""')}"`;
}

function exportCSV() {
  const header = ["اسم الوحدة", "النوع", "الرمز", "الوحدة الأعلى", "الحالة"];
  const rows = sortedUnits().map((unit) => [
    unit.name,
    UNIT_TYPES[unit.type].label,
    unit.code,
    getParent(unit)?.name || "",
    unit.status === "active" ? "نشطة" : "غير نشطة",
  ]);
  const csv = `\uFEFF${[header, ...rows].map((row) => row.map(csvCell).join(",")).join("\r\n")}`;
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = "university-structure.csv";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  showToast("تم تجهيز ملف CSV للهيكل الأكاديمي.");
}

document.addEventListener("click", (event) => {
  const viewButton = event.target.closest("[data-view]");
  if (viewButton) {
    event.preventDefault();
    setView(viewButton.dataset.view);
  }

  const actionButton = event.target.closest("[data-action]");
  if (!actionButton) return;
  if (actionButton.dataset.action === "add-unit") openDialog();
  if (actionButton.dataset.action === "edit") {
    const unit = state.units.find((candidate) => candidate.id === actionButton.dataset.id);
    if (unit) openDialog(unit);
  }
  if (actionButton.dataset.action === "delete") deleteUnit(actionButton.dataset.id);
});

document.getElementById("unit-type").addEventListener("change", () => updateParentOptions());
document.getElementById("close-dialog").addEventListener("click", closeDialog);
document.getElementById("cancel-dialog").addEventListener("click", closeDialog);
elements.form.addEventListener("submit", saveUnit);
elements.search.addEventListener("input", renderUnits);
elements.filter.addEventListener("change", renderUnits);
document.getElementById("export-button").addEventListener("click", exportCSV);
document.getElementById("refresh-monitor").addEventListener("click", refreshMonitor);
window.addEventListener("online", refreshMonitor);
window.addEventListener("offline", refreshMonitor);
document.getElementById("mobile-menu").addEventListener("click", (event) => {
  const sidebar = document.getElementById("sidebar");
  const isOpen = sidebar.classList.toggle("is-open");
  event.currentTarget.setAttribute("aria-expanded", String(isOpen));
});
elements.dialog.addEventListener("click", (event) => {
  if (event.target === elements.dialog) closeDialog();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "/" && !elements.dialog.open && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) {
    event.preventDefault();
    setView("units");
    elements.search.focus();
  }
});

document.getElementById("today-date").textContent = new Intl.DateTimeFormat("ar", { weekday: "long", day: "numeric", month: "long" }).format(new Date());
try {
  if (!localStorage.getItem(STORAGE_KEY)) persist();
} catch (error) {
  console.warn("التخزين المحلي غير متاح؛ ستعمل الصفحة دون حفظ التغييرات.", error);
}
renderAll();
refreshMonitor();