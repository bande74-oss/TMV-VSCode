# Scheda di Controllo Tecnico: Valori Diametro e Passo Aggiunti in RT05_DESCR_DIAM_PASSO

**Destinatario:** Ufficio Tecnico / Responsabile Tecnico di Prodotto TMV  
**Autore:** SOLVERIS - Bandera Marco  
**Data:** 24/09/2026  
**Ambiente Database:** `DBTMV` - Tabella `dbo.RT05_DESCR_DIAM_PASSO`  
**Oggetto:** Verifica e validazione umana dei parametri di derivazione diametro barra grezza per filettature metriche di grandi dimensioni (M110 - M180).

---

## 1. Regola Matematica di Calcolo Applicata

I valori di diametro base della barra pelata/trafilata inseriti in `RT05_DIAMETRO` seguono fedelmente la proporzione geometrica consolidata nello storico di TMV (derivata dal profilo ISO metrico a 60° per la rullatura/asportazione filetti):

$$\text{Diametro Base Barra (RT05\_DIAMETRO)} = \text{Diametro Nominale Filettatura} - \Delta_{\text{Passo}}$$

| Passo Filetto | Codice Passo Gamma | Delta Costante ($\Delta$) | Esempio Storico Consolidato |
| :---: | :---: | :---: | :--- |
| **3 mm** | **`3-`** | **2,00 mm** | M100x3 $\rightarrow$ $100 - 2,00 = \mathbf{98,00\text{ mm}}$ |
| **4 mm** | **`4-`** | **2,66 mm** | M100x4 $\rightarrow$ $100 - 2,66 = \mathbf{97,34\text{ mm}}$ |
| **6 mm** | **`G-`** | **3,98 mm** | M100x6 $\rightarrow$ $100 - 3,98 = \mathbf{96,02\text{ mm}}$ |

### Interazione con la Minorazione Commerciale (Categoria 2 del Configuratore)
Nel calcolo finale della descrizione per barre (`TDP`, `TDR`, `TDL`, `TDF`), la funzione sottrae la minorazione:
$$\text{Diametro Descrizione Finale} = \text{RT05\_DIAMETRO} - \frac{\text{Minorazione}}{10}$$
- *Esempio 1 (Minorazione '00' / Standard):* M125x4 $\rightarrow 122,34 - 0,00 = \mathbf{122,34\text{ mm}} \rightarrow \mathbf{\text{Ø 122,34mm}}$
- *Esempio 2 (Minorazione '04' / es. TDP04B7-M1254-):* M125x4 $\rightarrow 122,34 - 0,40 = \mathbf{121,94\text{ mm}} \rightarrow \mathbf{\text{Ø 121,94mm}}$

---

## 2. Tabella di Controllo per l'Ufficio Tecnico

La seguente tabella elenca in ordine di diametro crescente tutte le combinazioni aggiunte nella tabella `RT05_DESCR_DIAM_PASSO`:

| Filettatura | Codice Diametro | Codice Passo | Diam. Nominale (mm) | Passo Filetto (mm) | Delta ($\Delta$) (mm) | **Diametro Barra Base RT05 (mm)** | Esempio Descr. Base (Min. 00) | Esempio Descr. Min. 04 (-0,4mm) | Articoli Impattati nel DB | Note / Stato Precedente |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **M110x3** | `M110` | `3-` | 110 | 3 | 2,00 | **108,00** | Ø 108mm | Ø 107,6mm | 300 | *Aggiunto* (mancava in RT05) |
| **M110x4** | `M110` | `4-` | 110 | 4 | 2,66 | **107,34** | Ø 107,34mm | Ø 106,94mm | 397 | *Aggiunto* (mancava in RT05) |
| **M110x6** | `M110` | `G-` | 110 | 6 | 3,98 | **106,02** | Ø 106,02mm | Ø 105,62mm | Già presente | *Preesistente* nello storico TMV |
| **M120x3** | `M120` | `3-` | 120 | 3 | 2,00 | **118,00** | Ø 118mm | Ø 117,6mm | 3 | *Aggiunto* (mancava in RT05) |
| **M120x4** | `M120` | `4-` | 120 | 4 | 2,66 | **117,34** | Ø 117,34mm | Ø 116,94mm | 10 | *Aggiunto* (mancava in RT05) |
| **M120x6** | `M120` | `G-` | 120 | 6 | 3,98 | **116,02** | Ø 116,02mm | Ø 115,62mm | 4 | *Aggiunto* (mancava in RT05) |
| **M125x3** | `M125` | `3-` | 125 | 3 | 2,00 | **123,00** | Ø 123mm | Ø 122,6mm | 302 | *Aggiunto* (mancava in RT05) |
| **M125x4** | `M125` | `4-` | 125 | 4 | 2,66 | **122,34** | Ø 122,34mm | **Ø 121,94mm** | **404** | *Aggiunto* (caso TDP04B7-M1254-) |
| **M125x6** | `M125` | `G-` | 125 | 6 | 3,98 | **121,02** | Ø 121,02mm | Ø 120,62mm | 492 | *Aggiunto* (mancava in RT05) |
| **M130x3** | `M130` | `3-` | 130 | 3 | 2,00 | **128,00** | Ø 128mm | Ø 127,6mm | - | *Aggiunto* per completezza di gamma |
| **M130x4** | `M130` | `4-` | 130 | 4 | 2,66 | **127,34** | Ø 127,34mm | Ø 126,94mm | 2 | *Aggiunto* (mancava in RT05) |
| **M130x6** | `M130` | `G-` | 130 | 6 | 3,98 | **126,02** | Ø 126,02mm | Ø 125,62mm | - | *Aggiunto* per completezza di gamma |
| **M155x3** | `M155` | `3-` | 155 | 3 | 2,00 | **153,00** | Ø 153mm | Ø 152,6mm | 2 | *Aggiunto* (mancava in RT05) |
| **M155x4** | `M155` | `4-` | 155 | 4 | 2,66 | **152,34** | Ø 152,34mm | Ø 151,94mm | - | *Aggiunto* per completezza di gamma |
| **M155x6** | `M155` | `G-` | 155 | 6 | 3,98 | **151,02** | Ø 151,02mm | Ø 150,62mm | - | *Aggiunto* per completezza di gamma |
| **M160x3** | `M160` | `3-` | 160 | 3 | 2,00 | **158,00** | Ø 158mm | Ø 157,6mm | 300 | *Aggiunto* (mancava in RT05) |
| **M160x4** | `M160` | `4-` | 160 | 4 | 2,66 | **157,34** | Ø 157,34mm | Ø 156,94mm | 394 | *Aggiunto* (mancava in RT05) |
| **M160x6** | `M160` | `G-` | 160 | 6 | 3,98 | **156,02** | Ø 156,02mm | Ø 155,62mm | 714 | *Aggiunto* (mancava in RT05) |
| **M180x3** | `M180` | `3-` | 180 | 3 | 2,00 | **178,00** | Ø 178mm | Ø 177,6mm | - | *Aggiunto* per completezza di gamma |
| **M180x4** | `M180` | `4-` | 180 | 4 | 2,66 | **177,34** | Ø 177,34mm | Ø 176,94mm | - | *Aggiunto* per completezza di gamma |
| **M180x6** | `M180` | `G-` | 180 | 6 | 3,98 | **176,02** | Ø 176,02mm | Ø 175,62mm | 6 | *Aggiunto* (mancava in RT05) |

---

## 3. Punti di Attenzione per la Revisione UT
1. **Verifica Tolleranze di Laminazione/Trafilatura:** Confermare se per i diametri pesanti $\ge 120\text{ mm}$ le costanti di delta filettatura (2,00 mm per passo 3, 2,66 mm per passo 4 e 3,98 mm per passo 6) corrispondono esattamente alle specifiche dei tondi di partenza utilizzati in officina prima della rullatura.
2. **Casi Particolari o Fuori Standard:** Qualora l'ufficio tecnico utilizzi per specifici diametri grezzi sovradimensionati o tolleranze differenti (es. h11/k12 anziché h9/h10), il valore di `RT05_DIAMETRO` può essere rettificato puntualmente tramite un semplice comando `UPDATE` su `dbo.RT05_DESCR_DIAM_PASSO`.

