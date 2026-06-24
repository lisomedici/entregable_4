window.DEMO_SUMMARY = {
  total_polizas: 7261,
  activas: 1200,
  base_churn_temprano: 0.255,
  alto: 55,
  medio: 1118,
  bajo: 27,
  precision_top20_entregable_3: 0.491,
  roc_auc_entregable_3: 0.731,
  modelo_entregable_3: "XGBoost",
  prototipo: "Demo web estatica + API local opcional"
};

function money(n) {
  return Math.round(n).toLocaleString("es-AR");
}

function policyBase(i) {
  const marcas = ["FORD", "TOYOTA", "CHEVROLET", "FIAT", "CITROEN", "HONDA", "VOLKSWAGEN", "RENAULT"];
  const modelos = ["TERRITORY TITANIUM", "COROLLA XEI", "CRUZE PREMIER", "ARGO PRECISION", "C 3 PICASSO", "HR-V EXL", "GOLF HIGHLINE", "SANDERO STEPWAY"];
  const regiones = ["GBA", "CABA", "Interior"];
  const aseguradoras = ["zurich", "sura", "mercantilAndina", "allianz", "experta"];
  const idx = i % marcas.length;

  return {
    id_poliza: `DEMO-${String(i).padStart(4, "0")}`,
    numero_poliza: String(90000000 + i * 7919),
    patente: i === 4 ? "AG701WM" : `D${String(i).padStart(3, "0")}MO`,
    cliente: `Cliente demo ${String(i).padStart(3, "0")}`,
    email: `cl***${String(i).padStart(3, "0")}@demo.com`,
    telefono: `***${String(1000 + i).slice(-4)}`,
    estado: "activated",
    aseguradora: aseguradoras[i % aseguradoras.length],
    cobertura: i % 3 === 0 ? "Terceros completo premium" : "Todo riesgo franquicia",
    metodo_pago: i % 4 === 0 ? "bankAccount" : "creditCard",
    region: regiones[i % regiones.length],
    provincia: regiones[i % regiones.length] === "CABA" ? "Capital Federal" : regiones[i % regiones.length] === "GBA" ? "Buenos Aires" : "Interior",
    marca: marcas[idx],
    modelo: modelos[idx],
    fecha_inicio: `2026-${String((i % 6) + 1).padStart(2, "0")}-${String((i % 26) + 1).padStart(2, "0")}`,
    cuota: money(70000 + (i % 120) * 1250),
    comision: money(9000 + (i % 70) * 310)
  };
}

function reasonsFor(level) {
  if (level === "Alto") {
    return [
      { label: "cuota", text: "Cuota mensual alta", impact: 0.11 },
      { label: "aseguradora", text: "Aseguradora con churn sobre promedio", impact: 0.08 },
      { label: "renovacion", text: "Poliza nueva, no renovacion", impact: 0.06 }
    ];
  }
  if (level === "Medio") {
    return [
      { label: "cuota", text: "Cuota mensual media-alta", impact: 0.06 },
      { label: "cobertura", text: "Cobertura de terceros", impact: 0.04 }
    ];
  }
  return [
    { label: "perfil", text: "Sin driver critico dominante", impact: 0.01 }
  ];
}

function makePolicy(i, level, score) {
  const p = policyBase(i);
  p.score_churn = Math.round(score * 1000) / 1000;
  p.nivel_riesgo = level;
  p.accion_recomendada = level === "Alto"
    ? "Contactar en la primera semana y revisar dolor de precio/cobertura."
    : level === "Medio"
      ? "Seguimiento preventivo durante onboarding."
      : "Flujo normal de onboarding.";
  p.razones = reasonsFor(level);
  return p;
}

const policies = [];

for (let i = 1; i <= 55; i += 1) {
  policies.push(makePolicy(i, "Alto", 0.47 - (i % 30) * 0.002));
}

for (let i = 56; i <= 1173; i += 1) {
  policies.push(makePolicy(i, "Medio", 0.39 - (i % 180) * 0.001));
}

for (let i = 1174; i <= 1200; i += 1) {
  policies.push(makePolicy(i, "Bajo", 0.19 - (i % 25) * 0.003));
}

window.DEMO_POLICIES = policies.sort((a, b) => b.score_churn - a.score_churn);
