// TMV NKE Robot Monitor - Dashboard Script
// Connessione API e Gestione Stato Real-time

let currentTab = 'logs';
let searchDebounceTimer = null;

document.addEventListener('DOMContentLoaded', () => {
    initDashboard();
});

function initDashboard() {
    loadStatus();
    loadKpis();
    loadActiveTab();

    // Polling automatico ogni 10 secondi
    setInterval(() => {
        loadStatus();
        loadKpis();
        loadActiveTab();
    }, 10000);

    // Event listeners
    document.getElementById('searchInput').addEventListener('input', (e) => {
        clearTimeout(searchDebounceTimer);
        searchDebounceTimer = setTimeout(() => {
            if (currentTab === 'logs') loadLogs();
        }, 300);
    });
}

function switchTab(tab) {
    currentTab = tab;
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById(`tab-${tab}`).classList.add('active');

    if (tab === 'logs') {
        document.getElementById('searchInput').style.display = 'block';
    } else {
        document.getElementById('searchInput').style.display = 'none';
    }

    loadActiveTab();
}

function loadActiveTab() {
    if (currentTab === 'logs') {
        loadLogs();
    } else {
        loadQueue();
    }
}

async function loadStatus() {
    try {
        const res = await fetch('/api/status');
        const json = await res.json();
        if (json.success && json.data) {
            const data = json.data;
            const dot = document.getElementById('statusDot');
            const text = document.getElementById('statusText');

            if (data.nkeReachable && data.databaseConnected) {
                dot.className = 'status-dot online';
                text.innerText = 'Robot NKE Online & DBTMV Connesso';
            } else if (!data.databaseConnected) {
                dot.className = 'status-dot offline';
                text.innerText = 'DBTMV Non Raggiungibile';
            } else {
                dot.className = 'status-dot offline';
                text.innerText = 'WebAPI NKE (192.168.1.138:7171) Offline';
            }
        }
    } catch (e) {
        console.error('Errore caricamento status:', e);
    }
}

async function loadKpis() {
    try {
        const res = await fetch('/api/kpis');
        const json = await res.json();
        if (json.success && json.data) {
            const d = json.data;
            document.getElementById('kpiInCoda').innerText = d.inCoda;
            document.getElementById('kpiInviati').innerText = d.inviati24h;
            document.getElementById('kpiErrori').innerText = d.errori24h;
            document.getElementById('kpiLatenza').innerText = `${Math.round(d.latenzaMediaMs)} ms`;
        }
    } catch (e) {
        console.error('Errore caricamento KPI:', e);
    }
}

async function loadLogs() {
    const search = document.getElementById('searchInput').value;
    try {
        const res = await fetch(`/api/logs?page=1&pageSize=50&search=${encodeURIComponent(search)}`);
        const json = await res.json();
        const tbody = document.getElementById('tableBody');
        const thead = document.getElementById('tableHead');

        thead.innerHTML = `
            <tr>
                <th>Data/Ora</th>
                <th>Documento / Riga</th>
                <th>Cliente</th>
                <th>Articolo</th>
                <th>Variante</th>
                <th>Tempo</th>
                <th>Esito Chiamata</th>
                <th>Operatore</th>
                <th>Azione</th>
            </tr>
        `;

        if (!json.success || !json.data || json.data.length === 0) {
            tbody.innerHTML = `<tr><td colspan="9" style="text-align:center; padding: 24px; color: #94A3B8;">Nessun record di log trovato.</td></tr>`;
            return;
        }

        tbody.innerHTML = json.data.map(item => {
            const dateStr = new Date(item.dataOra).toLocaleString('it-IT', { hour12: false });
            const badgeClass = item.esitoGenerato ? 'badge-success' : (item.httpStatus === 408 ? 'badge-warning' : 'badge-danger');
            const statusLabel = item.esitoGenerato ? '200 OK - Generato' : (item.messaggioErrore ? item.messaggioErrore.substring(0, 35) : `HTTP ${item.httpStatus}`);

            return `
                <tr>
                    <td class="mono" style="color: #64748B;">${dateStr}</td>
                    <td style="font-weight: 600; color: #1E293B;">
                        ${item.documentiCollegati ? `<span class="badge-order">${escapeHtml(item.documentiCollegati)}</span>` : '<span style="color:#94A3B8;">-</span>'}
                    </td>
                    <td style="color: #334155; font-weight: 500;">${escapeHtml(item.clientiCollegati || 'TMV Standard')}</td>
                    <td class="mono" style="color: #0369A1; font-weight: 600;">${escapeHtml(item.codiceArticolo)}</td>
                    <td class="mono" style="color: #0F172A;">${escapeHtml(item.variante)}</td>
                    <td class="mono" style="color: #64748B;">${item.latenzaMs} ms</td>
                    <td><span class="badge ${badgeClass}">${escapeHtml(statusLabel)}</span></td>
                    <td style="font-size: 11px; color: #475569;">${escapeHtml(item.operatore)}</td>
                    <td>
                        <button class="btn btn-secondary" style="padding: 3px 8px; font-size: 11px;" onclick="viewPayload(${item.idLog})">
                            Vedi Dettaglio
                        </button>
                    </td>
                </tr>
            `;
        }).join('');
    } catch (e) {
        console.error('Errore caricamento logs:', e);
    }
}

async function loadQueue() {
    try {
        const res = await fetch('/api/queue');
        const json = await res.json();
        const tbody = document.getElementById('tableBody');
        const thead = document.getElementById('tableHead');

        thead.innerHTML = `
            <tr>
                <th>Data Inserimento</th>
                <th>Documenti Collegati</th>
                <th>Clienti</th>
                <th>Codice Articolo</th>
                <th>Variante</th>
                <th>Tentativi</th>
                <th>Stato Coda</th>
                <th>Sovrascrittura</th>
            </tr>
        `;

        if (!json.success || !json.data || json.data.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" style="text-align:center; padding: 24px; color: #94A3B8;">Coda vuota: nessun articolo in attesa per NKE.</td></tr>`;
            return;
        }

        tbody.innerHTML = json.data.map(item => {
            const dateStr = new Date(item.dataInserimento).toLocaleString('it-IT', { hour12: false });
            return `
                <tr>
                    <td class="mono" style="color: #64748B;">${dateStr}</td>
                    <td><span class="badge-order">${escapeHtml(item.documentiCollegati || 'Ordine Non Tracciato')}</span></td>
                    <td style="color: #334155; font-weight: 500;">${escapeHtml(item.clientiCollegati || '-')}</td>
                    <td class="mono" style="color: #0369A1; font-weight: 600;">${escapeHtml(item.codiceArticolo)}</td>
                    <td class="mono" style="color: #0F172A;">${escapeHtml(item.variante)}</td>
                    <td class="mono" style="font-weight: 600;">${item.tentativi} / 3</td>
                    <td><span class="badge badge-warning">In Coda Dispatcher</span></td>
                    <td>${item.sovrascrivi ? '<span class="badge badge-danger">Sì (@Forza)</span>' : '<span style="color:#94A3B8;">No</span>'}</td>
                </tr>
            `;
        }).join('');
    } catch (e) {
        console.error('Errore caricamento coda:', e);
    }
}

async function simulateOrder() {
    const numDoc = parseInt(document.getElementById('inputNumDoc').value);
    if (!numDoc || isNaN(numDoc)) {
        alert('Inserisci un numero di conferma d\'ordine valido (es. 5519).');
        return;
    }

    try {
        const res = await fetch('/api/orders/simulate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ numDoc: numDoc })
        });
        const json = await res.json();

        if (json.success && json.data) {
            showSimulationModal(numDoc, json.data);
        } else {
            alert('Errore simulazione: ' + (json.message || 'Errore sconosciuto'));
        }
    } catch (e) {
        alert('Errore di comunicazione con il server: ' + e.message);
    }
}

function showSimulationModal(numDoc, rows) {
    const modal = document.getElementById('detailModal');
    const title = document.getElementById('modalTitle');
    const body = document.getElementById('modalBody');

    title.innerText = `Simulazione Dry-Run Ordine CO ${numDoc} (${rows.length} righe analizzate)`;

    if (rows.length === 0) {
        body.innerHTML = `<p style="padding: 20px; color: #64748B; text-align: center;">Nessuna riga utile per NKE trovata per l'ordine ${numDoc}.</p>`;
    } else {
        body.innerHTML = `
            <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
                <thead>
                    <tr style="background:#F1F5F9;">
                        <th style="padding: 8px;">Riga</th>
                        <th style="padding: 8px;">Cliente</th>
                        <th style="padding: 8px;">Articolo</th>
                        <th style="padding: 8px;">Variante</th>
                        <th style="padding: 8px;">Stato Riga</th>
                        <th style="padding: 8px;">Esito Delta</th>
                        <th style="padding: 8px;">Motivazione</th>
                    </tr>
                </thead>
                <tbody>
                    ${rows.map(r => `
                        <tr style="border-bottom: 1px solid #E2E8F0;">
                            <td style="padding: 8px; font-weight:600;">R.${r['Prog Riga'] || r.DO30_PROGRIGA}</td>
                            <td style="padding: 8px;">${escapeHtml(r['Cliente'] || r.RAGIONE_SOCIALE || '')}</td>
                            <td class="mono" style="padding: 8px; color: #0369A1;">${escapeHtml(r['Codice Articolo'] || r.DO30_CODART_MG66 || '')}</td>
                            <td class="mono" style="padding: 8px;">${escapeHtml(r['Variante'] || r.DO30_OPZIONE_MG5E || '')}</td>
                            <td style="padding: 8px;">${escapeHtml(r['Descrizione Stato Riga'] || '')}</td>
                            <td style="padding: 8px;">
                                <span class="badge ${r['Esito Delta'] === 'DA_INSERIRE_NUOVO' ? 'badge-success' : 'badge-warning'}">
                                    ${escapeHtml(r['Esito Delta'] || '')}
                                </span>
                            </td>
                            <td style="padding: 8px; color: #64748B;">${escapeHtml(r['Motivazione Operativa'] || '')}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }

    modal.style.display = 'flex';
}

async function forceOrder() {
    const numDoc = parseInt(document.getElementById('inputNumDoc').value);
    const operatore = document.getElementById('inputOperatore').value.trim() || 'UfficioTecnico';
    const forzaReinvio = document.getElementById('checkForza').checked;

    if (!numDoc || isNaN(numDoc)) {
        alert('Inserisci un numero di conferma d\'ordine valido (es. 5519).');
        return;
    }

    const conferma = confirm(`Confermi l'accodamento dell'ordine CO ${numDoc} per la generazione CAD NKE?\nOperatore: ${operatore}\nSovrascrivi file: ${forzaReinvio ? 'SÌ' : 'NO'}`);
    if (!conferma) return;

    try {
        const res = await fetch('/api/orders/force', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                numDoc: numDoc,
                forzaReinvio: forzaReinvio,
                operatore: operatore
            })
        });
        const json = await res.json();

        if (json.success) {
            alert(json.message || 'Ordine accodato con successo!');
            loadKpis();
            switchTab('queue');
        } else {
            alert('Errore: ' + (json.message || 'Errore imprevisto'));
        }
    } catch (e) {
        alert('Errore durante la richiesta di forzatura: ' + e.message);
    }
}

async function viewPayload(idLog) {
    try {
        const res = await fetch(`/api/logs/${idLog}/payload`);
        const json = await res.json();

        if (json.success && json.data) {
            const d = json.data;
            const modal = document.getElementById('detailModal');
            document.getElementById('modalTitle').innerText = `Dettaglio Chiamata NKE (ID Log: ${d.idLog})`;

            let prettyReq = d.richiestaJson;
            let prettyResp = d.rispostaJson;
            try { prettyReq = JSON.stringify(JSON.parse(d.richiestaJson), null, 2); } catch {}
            try { prettyResp = JSON.stringify(JSON.parse(d.rispostaJson), null, 2); } catch {}

            document.getElementById('modalBody').innerHTML = `
                <div style="margin-bottom: 16px;">
                    <h4 style="font-size: 13px; font-weight: 700; margin-bottom: 6px; color: #1E293B;">Richiesta JSON Inviata a NKE:</h4>
                    <pre class="json-viewer">${escapeHtml(prettyReq)}</pre>
                </div>
                <div>
                    <h4 style="font-size: 13px; font-weight: 700; margin-bottom: 6px; color: #1E293B;">Risposta Ricevuta:</h4>
                    <pre class="json-viewer" style="background-color: #1E293B;">${escapeHtml(prettyResp || '(Nessuna risposta)')}</pre>
                </div>
                ${d.messaggioErrore ? `
                    <div style="margin-top: 14px; padding: 10px; background-color: #FEE2E2; border-radius: 4px; color: #B91C1C; font-size: 12px;">
                        <strong>Dettaglio Errore:</strong> ${escapeHtml(d.messaggioErrore)}
                    </div>
                ` : ''}
            `;

            modal.style.display = 'flex';
        }
    } catch (e) {
        alert('Impossibile caricare il dettaglio della chiamata: ' + e.message);
    }
}

function closeModal() {
    document.getElementById('detailModal').style.display = 'none';
}

function escapeHtml(text) {
    if (!text) return '';
    return text.toString()
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

