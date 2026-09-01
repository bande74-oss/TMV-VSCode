# Regole di Comportamento e Sviluppo SQL (Progetto TMV)

Queste regole devono essere applicate automaticamente dall'agente ad ogni operazione di creazione, modifica o revisione di componenti SQL (Tabelle, Viste, Stored Procedure, ecc.) e per la redazione della relativa documentazione.

## 1. Pianificazione e Analisi
- **Piano di azione:** Prima di scrivere o modificare codice, proponi un piano di azione dettagliato. Fai tutte le domande necessarie per chiarire i requisiti o richiedere elementi mancanti prima di agire (Planning Mode).
- **Versione SQL:** Assicurati di conoscere la versione di SQL Server in uso. Se non dichiarata, chiedila all'inizio della sessione per evitare incompatibilità.

## 2. Standard di Codifica SQL
- **Cartiglio Narrativo Obbligatorio:** Ogni script deve iniziare con un cartiglio che "racconti una storia". Deve contenere:
  - Data e Ora di creazione/modifica.
  - Autore: `SOLVERIS - Bandera Marco`.
  - **Descrizione ad altissimo dettaglio:** Una spiegazione prolissa, esplicita e chiara dello scopo dell'oggetto SQL. Deve far risparmiare energia mentale a chi rilegge il codice a distanza di tempo, spiegando ampiamente il contesto aziendale e tecnico.
- **Transazioni e Sicurezza:** Usa sempre blocchi `TRY...CATCH` e `BEGIN TRAN ... COMMIT / ROLLBACK` per operazioni di modifica dati (DML).
  - *Eccezione:* Ignora questa regola per script di creazione/modifica di strutture (DDL come `CREATE/ALTER TABLE` o `VIEW`), limitandoti al codice strutturale.
- **Letture senza blocchi:** Applica logiche per non produrre blocchi sulle tabelle in caso di query di sola lettura (es. l'uso di `WITH (NOLOCK)`).
- **Collation:** Gestisci correttamente la `COLLATE` per evitare conflitti, prestando particolare attenzione quando si generano tabelle temporanee (`#temp`). Se non specificata, usa il collate di default del DB in uso.
- **Nomenclatura GEMINI:** Nel caso in cui il nome dell'oggetto SQL da creare o revisionare non lo preveda già, aggiungi il suffisso `_GEMINI` al nome.
- **Commenti Prolissi nel Codice:** Inserisci spiegazioni dettagliate, quasi discorsive, direttamente nel corpo del codice. L'obiettivo è minimizzare il carico cognitivo futuro: chi rilegge (anche dopo mesi) deve poter capire immediatamente l'intento aziendale e logico, senza dover decifrare la sintassi SQL. Concentrati fortemente sul "perché" (la logica di business) viene fatta un'azione.

## 3. Stored Procedure (Modalità Dry-Run / DryOut)
- **Modalità Sicura di Default:** Tutte le Stored Procedure generate o pesantemente modificate devono prevedere, per default, una modalità di esecuzione "Dry-Run" (DryOut).
- In questa modalità, la procedura non deve in nessun modo modificare, aggiornare o inserire nulla nel Database, ma deve produrre risultati *Verbosi* per permettere all'utente di controllare esattamente quali azioni verrebbero eseguite.

## 4. Gestione Versioni e Revisioni (Change Log Narrativo)
- **Storico nel Cartiglio (Mai Ridondante):** Mantieni sempre traccia di ogni singola modifica in un'apposita sezione "Change Log" o "Storico Revisioni" all'interno del cartiglio (es. `Rev. 1`, `Rev. 2`, ecc.). 
- **Dettaglio Estremo e Intoccabile:** Per ogni revisione, descrivi prolissamente *cosa* è cambiato, *perché* è stato necessario il cambiamento e l'impatto atteso. Anche se può sembrare ridondante, il cartiglio deve farsi carico di raccontare tutto il ciclo di vita dell'oggetto. **Non cancellare o accorciare mai** lo storico delle revisioni precedenti.

## 5. Documentazione Tecnica SQL
Quando viene esplicitamente richiesta la redazione di un "documento tecnico SQL", conformati allo stile dell'impianto attualmente realizzato e struttura l'output in queste parti:
- **Parte 1 (Logiche di Business):** Sezione discorsiva, molto dettagliata e potenzialmente prolissa, scritta con l'obiettivo di essere facilmente compresa da un "non addetto ai lavori" o dall'utente finale.
- **Parte 2 (Scelte Tecniche):** Sezione molto dettagliata, indirizzata a un potenziale collega sviluppatore (per handover di gestione e manutenzione). Spiega a fondo le scelte tecniche adottate.
- **Parte 3 (Appendice Sorgenti - su richiesta):** Chiedi sempre all'utente se desidera integrare il documento con una terza parte contenente tutti gli script per esteso.
