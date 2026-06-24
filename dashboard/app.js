const state = {
  policies: [],
  filtered: []
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
  const summary = await getJson("/api/summary");
  el("activeCount").textContent = summary.activas.toLocaleString("es-AR");
  el("highCount").textContent = summary.alto.toLocaleString("es-AR");
  el("baseRate").textContent = pct(summary.base_churn_temprano);
  el("precisionTop20").textContent = pct(summary.precision_top20_entregable_3);
}

async function loadPolicies() {
  const limit = Number(el("limitInput").value || 80);
  const reveal = el("revealContact").checked ? "1" : "0";
  state.policies = await getJson(`/api/policies?limit=${limit}&reveal=${reveal}`);
  applyFilters();
}

function applyFilters() {
  const query = el("searchInput").value.trim().toLowerCase();
  const risk = el("riskFilter").value;

  state.filtered = state.policies.filter((p) => {
    const matchesRisk = risk === "todos" || p.nivel_riesgo === risk;
    const blob = `${p.id_poliza} ${p.numero_poliza} ${p.patente} ${p.cliente} ${p.email} ${p.telefono} ${p.marca} ${p.modelo}`.toLowerCase();
    return matchesRisk && (!query || blob.includes(query));
  });

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

function renderPolicies() {
  const body = el("policiesBody");
  body.innerHTML = "";
  el("tableCaption").textContent = `${state.filtered.length} polizas visibles, ordenadas por score descendente.`;

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
        <span class="subtle">${p.region} · ${p.aseguradora}</span>
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

async function predict(event) {
  event.preventDefault();
  const payload = formToObject(event.currentTarget);
  const result = await getJson("/api/predict", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  renderPrediction(result);
}

async function refreshAll() {
  try {
    await loadSummary();
    await loadPolicies();
    showToast("Dashboard actualizado");
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

el("refreshBtn").addEventListener("click", refreshAll);
el("searchInput").addEventListener("input", applyFilters);
el("riskFilter").addEventListener("change", applyFilters);
el("limitInput").addEventListener("change", loadPolicies);
el("revealContact").addEventListener("change", loadPolicies);
el("predictForm").addEventListener("submit", predict);
el("copyBtn").addEventListener("click", copyTop10);

refreshAll();
