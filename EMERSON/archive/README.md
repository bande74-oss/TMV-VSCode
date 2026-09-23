# Archivio Versioni Storiche - Modulo EMERSON (TMV)

In questa cartella sono archiviate le versioni storiche delle funzioni di recupero lotti (`SPRT_LTT_FAKE`), dismesse dal database di produzione `[DBTMV]` in data **23/09/2026** per eliminazione del debito tecnico e prevenzione di table scan.

---

## 1. Elenco Oggetti Archiviati

### A. [`SPRT_LTT_FAKE_OLD.sql`](./SPRT_LTT_FAKE_OLD.sql)
- **Data Creazione:** 17/03/2024
- **Autore:** SOLVERIS - Bandera Marco
- **Descrizione:** Prima implementazione funzionante dell'algoritmo deduttivo a priori basato su distinta base master (`PD95/PD96`), anagrafica lotti (`MG4G`) e progressivi di magazzino (`MG7G/MG7I`).
- **Motivo Dismissione:** Non teneva conto dell'avanzamento reale di officina (non verificava se la produzione avesse già registrato lo scarico fisico del materiale). La sua intera logica è stata incorporata come **STEP 2 (Fallback)** all'interno della versione definitiva [`SPRT_LTT_FAKE.sql`](../SPRT_LTT_FAKE.sql).

### B. [`SPRT_LTT_FAKE_OLD_2026_03_04.sql`](./SPRT_LTT_FAKE_OLD_2026_03_04.sql)
- **Data Creazione:** 04/03/2026 15:35
- **Autore:** SOLVERIS - Bandera Marco
- **Descrizione:** Snapshot di backup del primo tentativo di implementazione dello STEP 1 per la risalita documentale da ODL allo scarico di produzione (`INT-SCARPROD`).
- **Motivo Dismissione:** Formulato come una JOIN monolitica diretta a 5 tabelle (`DO30` -> `DO33` -> `DO11` -> `DO52` -> `MG4G`), causava **table scan incrociati e rallentamenti critici** all'interno della Scalar UDF. È stato superato e sostituito dalla versione definitiva [`SPRT_LTT_FAKE.sql`](../SPRT_LTT_FAKE.sql) che scompone lo STEP 1 in due fasi mirate con Index Seek su `DO33` e aggiunge il supporto alla sezione `'LOTTO'`.

---

> [!NOTE]
> Per qualsiasi nuova implementazione o interrogazione analitica, fare riferimento unicamente ai componenti attivi nella cartella genitore `EMERSON/`.

