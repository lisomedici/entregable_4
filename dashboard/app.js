const state = {
  policies: [],
  totalMatches: 0,
  filtered: [],
  demoMode: false
};

const el = (id) => document.getElementById(id);

function pct(value) {
  return `${Math.round(Number(value) * 1000) / 10}%`;
}

function showToast(message) {
  const toast = el("toast");
  toast.textContent = message;
  toast.classList.add("show");
  window.setTimeout(() => toast.classList.remove("show"), 2200);
}

async function getJson(url, options) {
  const res = await fetch(url, options);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `HTTP ${res.status}`);
  }
  return res.json();
}

async function loadSummary() {
  let summary;
  try {
    summary = await getJson("/api/summary");
    state.demoMode = false;
  } catch {
    summary = window.DEMO_SUMMARY;
    state.demoMode = true;
  }
  if (el("activeCount")) el("activeCount").textContent = summary.activas.toLocaleString("es-AR");
  if (el("highCount")) el("highCount").textContent = summary.alto.toLocaleString("es-AR");
  if (el("baseRate")) el("baseRate").textContent = pct(summary.base_churn_temprano);
  if (el("precisionTop20")) el("precisionTop20").textContent = pct(summary.precision_top20_entregable_3);
}

async function loadPolicies() {
  const reveal = el("revealContact").checked ? "1" : "0";
  try {
    state.policies = await getJson(`/api/policies?limit=5000&reveal=${reveal}`);
    state.demoMode = false;
  } catch {
    state.policies = window.DEMO_POLICIES || [];
    state.demoMode = true;
  }
  applyFilters();
}

function applyFilters() {
  const query = el("searchInput").value.trim().toLowerCase();
  const risk = el("riskFilter").value;
  const limit = Number(el("limitInput").value || 80);

  const matches = state.policies.filter((p) => {
    const matchesRisk = risk === "todos" || p.nivel_riesgo === risk;
    const blob = `${p.id_poliza} ${p.numero_poliza} ${p.patente} ${p.cliente} ${p.email} ${p.telefono} ${p.marca} ${p.modelo}`.toLowerCase();
    return matchesRisk && (!query || blob.includes(query));
  });
  state.totalMatches = matches.length;
  state.filtered = matches.slice(0, limit);

  renderPolicies();
}

function riskCell(p) {
  return `
    <span class="risk ${p.nivel_riesgo}">${p.nivel_riesgo}</span>
    <span class="score">${pct(p.score_churn)}</span>
  `;
}

function reasonsHtml(reasons) {
  if (!reasons || !reasons.length) return "<span class=\"subtle\">Sin driver dominante</span>";
  return `<ul class="reason-list">${reasons.map((r) => `<li>${r.text}</li>`).join("")}</ul>`;
}

function countBy(items, keyFn) {
  const map = new Map();
  items.forEach((item) => {
    const key = keyFn(item) || "Sin dato";
    map.set(key, (map.get(key) || 0) + 1);
  });
  return [...map.entries()]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

function highRiskItems() {
  return state.policies.filter((p) => p.nivel_riesgo === "Alto");
}

function renderBarChart(id, rows, options = {}) {
  const container = el(id);
  if (!container) return;
  const max = Math.max(...rows.map((r) => r.value), 1);
  const total = options.total || rows.reduce((sum, r) => sum + r.value, 0) || 1;
  const limit = options.limit || rows.length;
  const colorClass = options.colorClass || "";

  container.innerHTML = rows.slice(0, limit).map((row) => {
    const width = Math.max(3, Math.round((row.value / max) * 100));
    const suffix = options.percent ? ` (${pct(row.value / total)})` : "";
    return `
      <div class="bar-row">
        <div class="bar-label">${row.label}</div>
        <div class="bar-track"><div class="bar-fill ${colorClass}" style="width:${width}%"></div></div>
        <div class="bar-value">${row.value}${suffix}</div>
      </div>
    `;
  }).join("");
}

function renderInsights() {
  if (!state.policies.length) return;

  const high = highRiskItems();
  const riskRows = [
    { label: "Alto", value: high.length },
    { label: "Medio", value: state.policies.filter((p) => p.nivel_riesgo === "Medio").length },
    { label: "Bajo", value: state.policies.filter((p) => p.nivel_riesgo === "Bajo").length }
  ];
  const insurerRows = countBy(high, (p) => p.aseguradora);
  const paymentRows = countBy(high, (p) => p.metodo_pago);
  const regionRows = countBy(high, (p) => p.region);
  const driverRows = countBy(high.flatMap((p) => p.razones || []), (r) => r.text);

  const mainInsurer = insurerRows[0] || { label: "-", value: 0 };
  const mainPayment = paymentRows[0] || { label: "-", value: 0 };
  const suggestedDailyContacts = Math.min(25, high.length);

  el("campaignTitle").textContent = `${mainInsurer.label} + ${mainPayment.label}`;
  el("campaignText").textContent = `Priorizar ${suggestedDailyContacts} contactos de alto riesgo con foco en precio, cobertura y onboarding.`;
  el("concentrationTitle").textContent = `${mainInsurer.label}: ${mainInsurer.value}`;
  el("concentrationText").textContent = `Es la aseguradora con mas polizas de alto riesgo dentro del universo evaluado.`;
  el("coverageTitle").textContent = `${high.length} casos altos`;
  el("coverageText").textContent = `${pct(high.length / state.policies.length)} de la cartera evaluada requiere contacto inmediato.`;

  renderBarChart("riskChart", riskRows, { total: state.policies.length, percent: true });
  renderBarChart("insurerChart", insurerRows, { total: high.length, percent: true, limit: 6, colorClass: "high" });
  renderBarChart("paymentChart", paymentRows, { total: high.length, percent: true, limit: 4, colorClass: "mid" });
  renderBarChart("regionChart", regionRows, { total: high.length, percent: true, limit: 4 });
  renderBarChart("driverChart", driverRows, { total: high.length, percent: true, limit: 8, colorClass: "high" });
}

function renderPolicies() {
  const body = el("policiesBody");
  body.innerHTML = "";
  const mode = state.demoMode ? "Modo web demo con datos anonimizados generados desde el CSV. " : "";
  el("tableCaption").textContent = `${mode}${state.totalMatches} coincidencias; mostrando ${state.filtered.length}, ordenadas por score descendente.`;

  if (!state.filtered.length) {
    body.innerHTML = `<tr><td colspan="7">No hay polizas para los filtros seleccionados.</td></tr>`;
    return;
  }

  const rows = state.filtered.map((p) => `
    <tr>
      <td>${riskCell(p)}</td>
      <td>
        <strong>${p.id_poliza || "-"}</strong>
        <span class="subtle">${p.numero_poliza || ""}</span>
        <span class="subtle">${p.patente || ""}</span>
      </td>
      <td>
        <strong>${p.cliente || "Sin nombre"}</strong>
        <span class="subtle">${p.region} - ${p.aseguradora}</span>
      </td>
      <td>
        <strong>${p.telefono || "-"}</strong>
        <span class="subtle">${p.email || ""}</span>
      </td>
      <td>
        <strong>${p.marca || ""}</strong>
        <span class="subtle">${p.modelo || ""}</span>
        <span class="subtle">${p.cobertura || ""}</span>
      </td>
      <td>
        <strong>$ ${p.cuota || "-"}</strong>
        <span class="subtle">${p.metodo_pago || ""}</span>
      </td>
      <td>${reasonsHtml(p.razones)}</td>
    </tr>
  `).join("");

  body.innerHTML = rows;
  renderInsights();
}

function formToObject(form) {
  const data = new FormData(form);
  return Object.fromEntries(data.entries());
}

function renderPrediction(result) {
  const pred = result.prediction;
  const riskClass = pred.nivel_riesgo;
  el("predictionResult").innerHTML = `
    <div class="result-card">
      <div class="result-score">
        <strong>${pct(pred.score_churn)}</strong>
        <span class="risk ${riskClass}">${riskClass}</span>
      </div>
      <div>
        <strong>Accion recomendada</strong>
        <p>${pred.accion_recomendada}</p>
      </div>
      <div>
        <strong>Drivers principales</strong>
        ${reasonsHtml(pred.razones)}
      </div>
    </div>
  `;
}

function renderPredictionError(message) {
  el("predictionResult").innerHTML = `
    <div class="empty">
      <strong>No se puede calcular el score</strong>
      <p>${message}</p>
    </div>
  `;
}

function num(value) {
  const parsed = Number(String(value || "0").replace(/[^0-9.-]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function demoPredict(payload) {
  const allowedInsurers = ["zurich", "sura", "mercantilAndina", "allianz", "experta"];
  const allowedClusters = [
    "Terceros Completo Premium",
    "Terceros Completo",
    "Todo Riesgo con Franquicia Alta",
    "Todo Riesgo con Franquicia Baja"
  ];

  if (!allowedInsurers.includes(payload.Aseguradora)) {
    throw new Error("Selecciona una aseguradora valida del listado.");
  }
  if (!allowedClusters.includes(payload.Cluster_Detalle)) {
    throw new Error("Selecciona una cobertura valida del listado.");
  }

  let score = 0.255;
  const reasons = [];
  const aseguradora = String(payload.Aseguradora || "").toLowerCase();
  const cluster = String(payload.Cluster_Detalle || "");
  const metodo = String(payload.Metodo_de_pago || "");
  const cuota = num(payload.Valor_cuota_mes_pesos);
  const comision = num(payload.Comision_pesos);
  const anio = num(payload.anio_bien);
  const renovacion = num(payload.Es_renovacion_ID_poliza_anterior);

  if (aseguradora.includes("zurich")) {
    score += 0.10;
    reasons.push({ label: "aseguradora", text: "Aseguradora con mayor churn historico", impact: 0.10 });
  } else if (aseguradora.includes("sura")) {
    score += 0.08;
    reasons.push({ label: "aseguradora", text: "Aseguradora con churn sobre promedio", impact: 0.08 });
  } else if (aseguradora.includes("mercantil")) {
    score += 0.05;
    reasons.push({ label: "aseguradora", text: "Aseguradora con riesgo medio-alto", impact: 0.05 });
  }

  if (cluster.includes("Terceros")) {
    score += 0.04;
    reasons.push({ label: "cobertura", text: "Cobertura de terceros", impact: 0.04 });
  }
  if (metodo === "bankAccount") {
    score += 0.06;
    reasons.push({ label: "pago", text: "Metodo de pago CBU", impact: 0.06 });
  }
  if (cuota >= 150000) {
    score += 0.11;
    reasons.push({ label: "cuota", text: "Cuota mensual alta", impact: 0.11 });
  } else if (cuota >= 100000) {
    score += 0.06;
    reasons.push({ label: "cuota", text: "Cuota mensual media-alta", impact: 0.06 });
  }
  if (comision >= 22000) {
    score += 0.05;
    reasons.push({ label: "comision", text: "Comision alta", impact: 0.05 });
  }
  if (anio && 2026 - anio >= 8) {
    score += 0.04;
    reasons.push({ label: "vehiculo", text: "Vehiculo con mayor antiguedad", impact: 0.04 });
  }
  if (!renovacion) {
    score += 0.07;
    reasons.push({ label: "renovacion", text: "Poliza nueva, no renovacion", impact: 0.06 });
  } else {
    score -= 0.09;
  }

  score = clamp((score * 0.60) + 0.02, 0.03, 0.82);
  const nivel = score > 0.40 ? "Alto" : score >= 0.20 ? "Medio" : "Bajo";
  const accion = nivel === "Alto"
    ? "Contactar en la primera semana y revisar dolor de precio/cobertura."
    : nivel === "Medio"
      ? "Seguimiento preventivo durante onboarding."
      : "Flujo normal de onboarding.";

  return {
    input: payload,
    prediction: {
      score_churn: Math.round(score * 1000) / 1000,
      nivel_riesgo: nivel,
      accion_recomendada: accion,
      razones: reasons.sort((a, b) => b.impact - a.impact).slice(0, 3)
    }
  };
}

async function predict(event) {
  event.preventDefault();
  const payload = formToObject(event.currentTarget);
  let result;
  try {
    result = await getJson("/api/predict", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    state.demoMode = false;
  } catch {
    try {
      result = demoPredict(payload);
      state.demoMode = true;
    } catch (err) {
      renderPredictionError(err.message);
      return;
    }
  }
  renderPrediction(result);
}

async function refreshAll() {
  try {
    await loadSummary();
    await loadPolicies();
    showToast(state.demoMode ? "Demo web cargada" : "Dashboard actualizado");
  } catch (err) {
    console.error(err);
    showToast("Error al cargar datos");
  }
}

async function copyTop10() {
  const top = state.filtered.slice(0, 10).map((p, idx) => {
    return `${idx + 1}. ${p.id_poliza} | ${p.cliente} | ${p.telefono} | ${p.email} | riesgo ${p.nivel_riesgo} (${pct(p.score_churn)})`;
  }).join("\n");

  try {
    await navigator.clipboard.writeText(top);
    showToast("Top 10 copiado");
  } catch {
    showToast("No se pudo copiar");
  }
}

function switchView(viewId) {
  document.querySelectorAll(".tab-view").forEach((view) => {
    view.classList.toggle("active", view.id === viewId);
  });
  document.querySelectorAll(".tab").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.view === viewId);
  });
  if (viewId === "insightsView") renderInsights();
}

el("refreshBtn").addEventListener("click", refreshAll);
el("searchInput").addEventListener("input", applyFilters);
el("riskFilter").addEventListener("change", applyFilters);
el("limitInput").addEventListener("change", loadPolicies);
el("revealContact").addEventListener("change", loadPolicies);
el("predictForm").addEventListener("submit", predict);
el("copyBtn").addEventListener("click", copyTop10);
document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => switchView(tab.dataset.view));
});

refreshAll();
