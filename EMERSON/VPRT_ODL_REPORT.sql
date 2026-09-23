USE [DBTMV]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/* ========================================================================================
-- OGGETTO:             [dbo].[VPRT_ODL_REPORT]
-- TIPO OGGETTO:        VISTA (VIEW)
-- AMBIENTE/DATABASE:   MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
-- AUTORE:              SOLVERIS - Bandera Marco
-- DATA MODIFICA:       2026-09-22 14:15
--
-- ----------------------------------------------------------------------------------------
-- DESCRIZIONE FUNZIONALE E NARRATIVA (BUSINESS CONTEXT AD ALTISSIMO DETTAGLIO)
-- ----------------------------------------------------------------------------------------
-- La presente vista [dbo].[VPRT_ODL_REPORT] costituisce il componente informativo e di calcolo
-- nevralgico per l'intero sistema di pianificazione, produzione, marcatura e avanzamento 
-- operativo di Torneria Molinari Vincenzo (TMV).
--
-- CONTESTO INDUSTRIALE E DI REPARTO:
-- TMV opera nel settore della produzione di elementi di fissaggio ad altissime prestazioni 
-- (tiranti, prigionieri, barre filettate, viteria speciale e componenti flangiati) destinati 
-- ad impianti chimici, petrolchimici, offshore ed energetici (settore Power Generation e Oil&Gas).
-- In tale contesto, ogni singolo pezzo prodotto deve rispondere a requisiti metallurgici, dimensionali 
-- e di tracciabilità estremi, in conformità a standard internazionali (ASTM, ASME, EN, ISO) 
-- e alle rigide prescrizioni capitolari dei committenti.
--
-- RUOLO DELLA VISTA NELLA REPORTISTICA AZIENDALE:
-- La vista funge da fonte dati unificata e normalizzata per:
-- 1. I Cartellini di Lavorazione / Viaggiatori di Produzione (ODL): documenti fisici e digitali
--    che accompagnano i lotti di materiale semilavorato attraverso i reparti (taglio, intestatura, 
--    tornitura, rullatura/filettatura, trattamenti termici, trattamenti superficiali, collaudo).
-- 2. Le Schede di Marcatura e Punzonatura (Laser / Meccanica a percussione): determinazione 
--    dei testi di timbratura (norma, classe, grado materiale, marchio TMV, sigla di colata, 
--    lotto fornitore e serial number).
-- 3. Le Istruzioni Operative di Officina: quote geometriche critiche (es. diametro di preparazione 
--    del tondo prima della rullatura dei filetti), calcoli di taglio barre commerciali (resa 
--    di troncatura a disco vs seghetto a nastro, sfridi e spessori di taglio).
-- 4. Monitoraggio Avanzamento Commerciale e Spedizioni: riconciliazione tra l'Ordine Cliente (OC), 
--    l'Ordine di Fabbricazione (ODL), i documenti di preparazione/imballo (Pre-DDT, Packing List) 
--    e le bolle di vendita definitive (DDT).
--
-- FOCUS SPECIFICO COMMESSE "EMERSON" E CLIENTI CRITICI:
-- Un pilastro portante della vista è la gestione specializzata del cliente EMERSON (e committenti analoghi).
-- Tali clienti impongono un grado di controllo e reportistica speciale:
-- - Posizione d'ordine specifica del cliente (estratta da DO35_ALFPERS10, es. PO line item) 
--   con priorità rispetto al progressivo riga interno.
-- - Gestione lotti cliente fornitore dedicati (LOTTO_KB_EMERSON), garantendo il recupero deterministico 
--   dell'ultimo lotto registrato senza generare duplicazioni nel flusso dati.
-- - Tracciabilità univoca attraverso codifiche proprietarie unificate TMV: BATCHCODE (primi 8 caratteri) 
--   ed HEATCODE (caratteri da 6 a 8 identificativi della colata di acciaio), generati mediante la 
--   funzione centralizzata [dbo].[SPRT_TMV_SHARED_BATCHCODE].
-- - Cascata di ereditarietà a due livelli per Lavorazioni Extra (Trattamenti 1, 2, 3) e Certificati 
--   (verifica prioritaria sulla riga d'ordine con risalita alla testata documento).
-- - Identificazione visiva rapida di reparto tramite "Color Corde" (marcatura a vernice sul fascio).
-- - Determinazione automatica della quota del diametro medio di rullatura (+0/-0.05 mm) con 
--   gestione puntuale delle eccezioni di capitolato (esclusione opzione 'HGE').
--
-- ----------------------------------------------------------------------------------------
-- STORICO REVISIONI (CHANGE LOG NARRATIVO COMPLETO E INTOCCABILE)
-- ----------------------------------------------------------------------------------------
-- Rev. 1
-- Data/Ora Modifica: 2026-03-04 09:25
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Risoluzione anomalia moltiplicazione righe (prodotto cartesiano) su OC_DO33_PROPRIO
-- Dettaglio:         In presenza di ordini cliente aventi molteplici registrazioni o legami documentali 
--                    incrociati nella tabella di raccordo dbo.DO33_DOCCORPORIF, la vista generava 
--                    permutazioni anomale con duplicazione e triplicazione delle righe dell'ODL.
--                    L'intervento ha inserito il filtro esplicito "OC_DO33_PROPRIO.DO33_PROGRIF = 1" 
--                    nella LEFT OUTER JOIN, vincolando la giunzione al primo legame univoco di riferimento 
--                    ed estirpando alla radice il prodotto cartesiano.
--
-- Rev. 2
-- Data/Ora Modifica: 2026-03-04 17:02
-- Autore:            SOLVERIS - Bandera Marco (Ottimizzazione Performance)
-- Oggetto:           Abbattimento lock contention e riscrittura architetturale per evitare Optimizer Timeout
-- Dettaglio:         1. Inserimento estensivo e sistematico dell'hint WITH (NOLOCK) su tutte le tabelle 
--                       coinvolte, azzerando i blocchi in lettura (dirty read ammesse per reportistica).
--                    2. Riscrittura completa delle pesanti sub-query correlate posizionate nella SELECT 
--                       (Diametro Medio, Marcatura/Marking, Sequenza Cut-off Barcode, Note Marcatura) 
--                       convertite in costrutti modulari OUTER APPLY (OA_DIAMETRO, OA_MARKING, 
--                       OA_SEQ_BARCODE, OA_NOTA_MARC). Tale refactoring ha sbloccato il parallelismo 
--                       del Query Optimizer di SQL Server, azzerando i timeout di esecuzione.
--                    3. Formattazione e riallineamento cosmetico del codice sorgente.
--
-- Rev. 3
-- Data/Ora Modifica: 2026-04-15 11:30
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Eliminazione permutazioni lotti Emerson e rettifica calcolo diametro per opzione HGE
-- Dettaglio:         1. Nel recupero dei dati del lotto Emerson da MG4G_ANAGRLOTTI + CO5L_ATTRIBUTIDEN, 
--                       la presenza di record storici multipli per articolo/opzione creava duplicazioni 
--                       nel report. È stato implementato il blocco OUTER APPLY con "TOP 1 ... ORDER BY 
--                       MG4G.MG4G_DATACRE DESC" (LOTTO_KB_EMERSON), garantendo l'estrazione deterministica 
--                       del solo lotto più recente.
--                    2. Nella formula del Diametro Medio (OA_DIAMETRO), è stata inserita la clausola 
--                       "and SUBSTRING(DO30_CICLI_FASE1400.DO30_OPZIONE_MG5E,6,3) <> 'HGE'" per 
--                       escludere gli articoli con trattamento speciale HGE dalla decurtazione di quota.
--
-- Rev. 4
-- Data/Ora Modifica: 2026-09-22 14:15
-- Autore:            SOLVERIS - Bandera Marco
-- Oggetto:           Predisposizione script formattato in repository e commenti narrativi integrali
-- Dettaglio:         1. Creazione del file .SQL strutturato all'interno della cartella di progetto EMERSON.
--                    2. Redazione del cartiglio narrativo approfondito e inserimento di commenti 
--                       discorsivi riga per riga per illustrare il contesto di business di ogni campo 
--                       e costrutto relazionale a beneficio dei futuri sviluppatori e manutentori.
--                    3. Nessuna modifica o correzione apportata al codice SQL operativo (conservazione 
--                       al 100% della logica e della sintassi originale in produzione).
-- ======================================================================================== */

CREATE OR ALTER VIEW [dbo].[VPRT_ODL_REPORT]
AS

/* ==============================================================================================================
   SEZIONE 1: IDENTIFICATIVI PRIMARI ORDINE DI LAVORO (ODL) ED ORDINE CLIENTE (OC)
   --------------------------------------------------------------------------------------------------------------
   Il costrutto SELECT DISTINCT assicura l'univocità della riga di report per ciascun abbinamento ODL-OC,
   prevenendo duplicati generati dalle relazioni 1-a-N esistenti con la distinta base (PD96) o con i cicli (PD48).
   Vengono estratti gli estremi dell'ordine di fabbricazione (ODL), dell'ordine commerciale cliente (OC)
   e la triade delle date di consegna (data contrattuale originaria, data confermata e data interna di officina).
   ============================================================================================================== */
SELECT DISTINCT	
				ODL_T.DO11_DOCUM_MG36 AS ODL_DO11_DOCUM_MG36
			,	ODL_T.DO11_NUMDOC AS ODL_DO11_NUMDOC
			,	ODL_T.DO11_DATADOC AS ODL_DO11_DATADOC
			,	ODL_C.DO30_DITTA_CG18
			,	ODL_C.DO30_NUMREG_CO99
			,	ODL_C.DO30_PROGRIGA
			,	ODL_C.DO30_IDDISBA_PD95
			,	OC_T.DO11_DOCUM_MG36 AS DocumOC
			,	OC_T.DO11_NUMDOC AS NumdocOC
			,	OC_T.DO11_DATADOC AS DataDocOC
			,	OC_C.DO30_NUMREG_CO99 AS NumRegOC
			,	OC_C.DO30_PROGRIGA AS ProgRigaOC
			,	OC_C.DO30_PROGVISUASTA AS ProgvisuastaOC
			,	OC_C.DO30_CODART_MG66 AS CodartOC
			,	ISNULL(OC_C.DO30_CODARTCLI,'') AS CodartCliOC
			,	DO31.DO31_DATACONSORIG
			,	DO31.DO31_DATACONS
			,	DO31.DO31_DATACONSINT
			
			/* ==============================================================================================================
   SEZIONE 2: SPECIFICHE COMMERCIALI, POSIZIONE CLIENTE (EMERSON PO ITEM) E NOTE QUALITÀ
   --------------------------------------------------------------------------------------------------------------
   - PosizioneOC: Emerson e i clienti strutturati trasmettono ordini d'acquisto con identificativi di riga specifici
     (PO Item, es. 00010, 00020), registrati in DO35_ALFPERS10. Se valorizzato, ha precedenza assoluta; 
     in caso contrario viene effettuato il fallback sul progressivo riga visivo DO30_PROGVISUASTA.
   - TassativaOC: flag prioritario di consegna rigida/tassativa (DO35_FLGPERS4) per il sequenziamento in officina.
   - OC_NoteQualita: prescrizioni speciali di qualità estratte prioritariamente dal campo esteso articolo (DO30) 
     o dalle note generali del documento (DO12).
   ============================================================================================================== */
			,	IIF(TRIM(ISNULL(OC_DO35.DO35_ALFPERS10,'')) = '', FORMAT(OC_C.DO30_PROGVISUASTA ,'#0'), TRIM(ISNULL(OC_DO35.DO35_ALFPERS10,''))) AS PosizioneOC
			,	ANAGGEN.CG16_RAGSOANAG AS ClienteOC
			,	ANAGGEN.CG16_ALIAS AS AliasClienteOC
			,	ISNULL(OC_DO35.DO35_FLGPERS4,0) AS TassativaOC
			,	IIF(TRIM(ISNULL(OC_C.DO30_ESTDESCART,'')) <> '', TRIM(ISNULL(OC_C.DO30_ESTDESCART,'')) , TRIM(ISNULL(OC_DO12.DO12_NOTENSDOC,''))) AS OC_NoteQualita

			/* ==============================================================================================================
   SEZIONE 3: LAVORAZIONI EXTRA, TRATTAMENTI SPECIALI E CERTIFICATI DI COLLAUDO
   --------------------------------------------------------------------------------------------------------------
   Logica gerarchica di ereditarietà a due livelli (Riga vs Testata):
   Le lavorazioni extra (trattamenti termici, galvanici, rivestimenti protettivi PTFE, zincatura, ecc.) 
   e i certificati di conformità (es. 3.1 / 3.2 EN 10204) possono essere specificati puntualmente sulla singola riga
   (tabelle DO36/DO35) oppure estesi a livello dell'intero ordine (tabelle DO20/DO17).
   La funzione IIF controlla in prima battuta la riga; in assenza di specifica, risale al default di testata.
   I codici vengono decodificati nelle descrizioni in chiaro tramite join su DO05_ANAGCAMPIPERS.
   - ColorCorde: identificativo colore verniciato sul fascio di materiale in officina per riconoscimento visivo rapido.
   - PathDisegnoAlternativo: percorso file del disegno tecnico cliente con fallback sul disegno master (PD18_RIFDIS).
   ============================================================================================================== */
			,	IIF(TRIM(ISNULL(OC_EXTRA_LAV_RIGA_1.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(OC_EXTRA_LAV_RIGA_1.DO05_DESCRIZIONE,'')), TRIM(ISNULL(OC_EXTRA_LAV_TESTATA_1.DO05_DESCRIZIONE,''))) AS OC_ExtraLav1
			,	IIF(TRIM(ISNULL(OC_EXTRA_LAV_RIGA_2.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(OC_EXTRA_LAV_RIGA_2.DO05_DESCRIZIONE,'')), TRIM(ISNULL(OC_EXTRA_LAV_TESTATA_2.DO05_DESCRIZIONE,''))) AS OC_ExtraLav2
			,	IIF(TRIM(ISNULL(OC_EXTRA_LAV_RIGA_3.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(OC_EXTRA_LAV_RIGA_3.DO05_DESCRIZIONE,'')), TRIM(ISNULL(OC_EXTRA_LAV_TESTATA_3.DO05_DESCRIZIONE,''))) AS OC_ExtraLav3
			,	IIF(TRIM(ISNULL(OC_CERT_RIGA.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(OC_CERT_RIGA.DO05_DESCRIZIONE,'')), TRIM(ISNULL(OC_CERT_TESTATA.DO05_DESCRIZIONE,''))) AS OC_Certificato
			,	IIF(TRIM(ISNULL(OC_DO36.DO36_ALFST8 ,'')) <> '', TRIM(ISNULL(OC_DO36.DO36_ALFST8,'')), TRIM(ISNULL(OC_DO20.DO20_ALFST8,''))) AS OC_ColorCorde
			,	ISNULL(COALESCE(OC_DO36.DO36_ALFST9, PD18_RIFDIS) ,'') AS OC_PathDisegnoAlternativo
		 
			,	IIF(TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_1.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_1.DO05_DESCRIZIONE,'')), TRIM(ISNULL(ODL_EXTRA_LAV_TESTATA_1.DO05_DESCRIZIONE,''))) AS ODL_ExtraLav1
			,	IIF(TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_2.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_2.DO05_DESCRIZIONE,'')), TRIM(ISNULL(ODL_EXTRA_LAV_TESTATA_2.DO05_DESCRIZIONE,''))) AS ODL_ExtraLav2
			,	IIF(TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_3.DO05_DESCRIZIONE,'')) <> '', TRIM(ISNULL(ODL_EXTRA_LAV_RIGA_3.DO05_DESCRIZIONE,'')), TRIM(ISNULL(ODL_EXTRA_LAV_TESTATA_3.DO05_DESCRIZIONE,''))) AS ODL_ExtraLav3
			,	IIF(TRIM(ISNULL(ODL_DO36.DO36_ALFST8 ,'')) <> '', TRIM(ISNULL(ODL_DO36.DO36_ALFST8,'')), TRIM(ISNULL(ODL_DO20.DO20_ALFST8,''))) AS ODL_ColorCorde
			,	ISNULL(COALESCE(ODL_DO36.DO36_ALFST9, PD18_RIFDIS),'') AS ODL_PathDisegnoAlternativo
	
			/* ==============================================================================================================
   SEZIONE 4: PARAMETRI DI OFFICINA, RULLATURA, MARCATURA MECCANICA E TRACCIABILITÀ LOTTI EMERSON
   --------------------------------------------------------------------------------------------------------------
   - DIAMETRO_MEDIO: Quota fondamentale per l'operatore di rullatura. Nelle filettature per deformazione plastica,
     il tondo preparato deve corrispondere al diametro medio del filetto teorico affinché il materiale formi le creste.
     Calcolato dinamicamente tramite OUTER APPLY (OA_DIAMETRO) con tolleranza d'officina +0/-0.05 mm.
   - MARKING: Testo di punzonatura meccanica/laser estratto da RT03_DESCRALTER per le fasi di timbratura (1250, 1270, 1271).
   - LOTTO_KB_EMERSON: Lotto registrato per il componente Emerson prelevato mediante OUTER APPLY deterministica (Rev. 3).
   - BATCHCODE & HEATCODE: Identificativi di colata e lotto interno TMV derivati da SPRT_TMV_SHARED_BATCHCODE.
   ============================================================================================================== */
			,	ODL_C.DO30_IDDISBA_PD95 AS ODL_ID_DISBA
			
			-- Ottimizzazione: Trasformato in OUTER APPLY (OA_DIAMETRO)
			,	ISNULL(OA_DIAMETRO.DIAMETRO_MEDIO, '0') AS DIAMETRO_MEDIO
		
			,	ISNULL(CO5L_OCL_C.CO5L_ALF90,'NO')	AS CARTELLINO

			-- Ottimizzazione: Trasformato in OUTER APPLY (OA_MARKING)
			,	ISNULL(OA_MARKING.MARKING, '') AS MARKING 

			-- Nota: Queste UDF scalari inibiscono il parallelismo, ove possibile dovrebbero diventare Inline TVF o JOIN
			,	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'CODLOTTO'),'') AS LOTTO_FAKE
			,	[dbo].[SPRT_LTT_FAKE_EMERSON](ODL_T.DO11_DITTA_CG18, PD96_COMPON, PD96_OPZIONE, IIF(TRIM(ISNULL(OC_DO36.DO36_ALFST1,'')) <> '', TRIM(ISNULL(OC_DO36.DO36_ALFST1,'')), '')) AS LOTTO_FAKE_EMERSON
			,	ISNULL(LOTTO_KB_EMERSON.CO5L_ALF102,'') AS LOTTO_KB_EMERSON

			,	SUBSTRING(
					IIF(ISNULL([dbo].[SPRT_TMV_SHARED_BATCHCODE](OC_C.DO30_DITTA_CG18 ,OC_C.DO30_NUMREG_CO99, OC_C.DO30_PROGRIGA),'') <> '',
						ISNULL([dbo].[SPRT_TMV_SHARED_BATCHCODE](OC_C.DO30_DITTA_CG18 ,OC_C.DO30_NUMREG_CO99, OC_C.DO30_PROGRIGA),''),
						CONVERT(CHAR(36),OC_C.DO30_GUID)
					), 1, 8) AS BATCHCODE
					
			,	SUBSTRING(
					IIF(ISNULL([dbo].[SPRT_TMV_SHARED_BATCHCODE](OC_C.DO30_DITTA_CG18 ,OC_C.DO30_NUMREG_CO99, OC_C.DO30_PROGRIGA),'') <> '',
						ISNULL([dbo].[SPRT_TMV_SHARED_BATCHCODE](OC_C.DO30_DITTA_CG18 ,OC_C.DO30_NUMREG_CO99, OC_C.DO30_PROGRIGA),''),
						CONVERT(CHAR(36),OC_C.DO30_GUID)
					), 6, 3) AS HEATCODE
					
			,	ISNULL(TIPO_PRODUZIONE.[DO36_INDST1],'0') AS COD_IND_CARTELLINO
			,	ISNULL(TIPO_PRODUZIONE.[DO05_DESCRIZIONE],'Non Definito') AS DESC_IND_CARTELLINO
			,	ISNULL([VPRT_CERT_HT_SIGLE_SUBSTITUTE].[RT03_MARKING_SUBSTITUTE],'') AS RT03_MARKING_SUBSTITUTE
			,	ISNULL(DO12_RIFVSDOC,'') AS DO12_RIFVSDOC
			,	ISNULL(DO12_NUMVSDOC,'') AS DO12_NUMVSDOC
			,	CG07_DESCR
			
			-- Altre funzioni scalari che potrebbero rallentare. Valutare conversione futura.
			,	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'COLATA'),'') AS COLATA
			,	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'COMPON'),'') AS COMPONENTE
			,	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'OPZIONE'),'') AS COMPONENTE_OPZIONE
			/* ==============================================================================================================
   SEZIONE 5: DATI TECNICI MATERIA PRIMA, QUOTE DI TAGLIO E CALCOLI RESA BARRE D'OFFICINA
   --------------------------------------------------------------------------------------------------------------
   - LUNGHEZZA_TAGLIO: Lunghezza netta finita del pezzo ordinato.
   - LUNGHEZZA_TAGLIO_FASI_1200_1215: Quota maggiorata per il taglio primario e l'intestatura delle estremità,
     calcolata sommando alla lunghezza nominale i sovrametalli definiti in RT11_VOLUMI_ALTEZZE.
   - PezziPerBarra_Troncatura vs PezziPerBarra_Seghetto: Formule matematiche di officina che determinano il numero 
     di particolari ricavabili da ciascuna barra commerciale (standard 3000 mm o 6000 mm), decurtando lo sfrido 
     fisiologico di presa alle due estremità (SfridoBarra) e lo spessore asportato dal disco/lama (SpessoreLama).
   - Fabbisogno Barre: Calcola il numero di barre piene da prelevare a magazzino per coprire il lotto di produzione.
   ============================================================================================================== */
			,	ISNULL(MG7A_UBICAZFIX,'') AS UBICAZIONE
			,	PD96_QUANT_2 AS	QTA2_CONSUMO
			,	OC_C.DO30_OPZIONE_MG5E AS VarianteOC
			,	OC_C.DO30_DESCART AS DesArtOC
			,	OC_DO33_PROPRIO.DO33_RIFVSDOC AS RifvsdoOC
			,	OC_DO33_PROPRIO.DO33_PROGRIF
			,	DDT.DO30_QTA1 AS QtaDDT
			,	DDT.DO11_DATADOC as DataDocDDT
			,	ISNULL(CO5L_ARTPF.CO5L_NOTE2,'') AS NOTE_AGGIUNTIVE_PRODUZIONE
			,	ISNULL(CO5L_ARTPF.CO5L_ALF98,'') AS REGOLA_MOLTIPLIC_LINGUETTE
			,	CO5L_ARTPF.CO5L_NUM66 AS LUNGHEZZA_TAGLIO
			,	IIF(ISNULL(RT11_VOLUMI_ALTEZZE.[RT11_OFFSET_TAGLIO], -1000) = -1000, 
					-1000, 
					CONVERT(INT, CONVERT(INT, REPLACE(SUBSTRING(OC_C.DO30_OPZIONE_MG5E,2,4),'-','')) + [RT11_ALTEZZA] + [RT11_OFFSET_TAGLIO]))
				AS LUNGHEZZA_TAGLIO_FASI_1200_1215
				
			,	0 AS NUMERO_RIGHE_100000
			,	ISNULL(PREDDT.DO30_QTA1,0) AS QtaPreDDT
			,	ISNULL(PKL.DO30_QTA1,0) AS QtaPKL
			,	PD96_COMPON
			,	PD96_OPZIONE
			,	ISNULL(OC_DO36.DO36_ALFST1,'') AS COLATA_TIMBRARE
			,	OC_CLIFOR.CG44_GUID
			,	ISNULL(MG66_FAM_MG53,'') AS MG66_FAM_MG53
			,	ISNULL(MG66_SFAM_MG54,'') AS MG66_SFAM_MG54

			-- Ottimizzazione: Trasformato in OUTER APPLY (OA_SEQ_BARCODE)
			,	OA_SEQ_BARCODE.SequenzaFaseCutOffStampaBarcode
			
			-- Ottimizzazione: Trasformato in OUTER APPLY (OA_NOTA_MARC)
			,	ISNULL(OA_NOTA_MARC.PD48_NOTA_MARCATURA, '') AS PD48_NOTA_MARCATURA
			
/* ==============================================================================================================
   SEZIONE 6: CLAUSOLA FROM E ARCHITETTURA DELLE JOIN RELAZIONALI
   --------------------------------------------------------------------------------------------------------------
   L'architettura delle relazioni parte dall'anagrafica cliente e dalla testata/corpo dell'Ordine Cliente (OC),
   si connette all'anagrafica tecnica dell'articolo prodotto (PD18), quindi tramite la tabella di legame documentale
   dbo.DO33_DOCCORPORIF si raccorda con l'Ordine di Lavoro di produzione (ODL, testata DO11 e corpo DO30).
   Tutte le tabelle adottano l'hint WITH (NOLOCK) per garantire letture non bloccanti in produzione concorrente.
   ============================================================================================================== */
FROM            dbo.VCG44_RAGSOCSOST WITH (NOLOCK)
		INNER JOIN dbo.DO11_DOCTESTATA AS OC_T WITH (NOLOCK)
			ON dbo.VCG44_RAGSOCSOST.DITTA = OC_T.DO11_DITTACF_CG44 
			AND dbo.VCG44_RAGSOCSOST.TIPOCF = OC_T.DO11_TIPOCF_CG44 
			AND dbo.VCG44_RAGSOCSOST.CLIFOR = OC_T.DO11_CLIFOR_CG44 
		INNER JOIN dbo.DO30_DOCCORPO AS OC_C WITH (NOLOCK)
			ON OC_T.DO11_DITTA_CG18 = OC_C.DO30_DITTA_CG18 
			AND OC_T.DO11_NUMREG_CO99 = OC_C.DO30_NUMREG_CO99 
		INNER JOIN PD18_ARTPROD WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = PD18_DITTA_CG18
			AND	OC_C.DO30_CODART_MG66 = PD18_CODART_MG66
		INNER JOIN dbo.CG16_ANAGGEN AS ANAGGEN WITH (NOLOCK)
			ON dbo.VCG44_RAGSOCSOST.CG16_CODICE = ANAGGEN.CG16_CODICE 
		LEFT JOIN CG07_TABSTATIEST WITH (NOLOCK)
			ON ANAGGEN.CG16_CODICE_CG07 = CG07_CODICE
				-- --- COLLEGAMENTO DOCUMENTALE TRA ORDINE CLIENTE (OC) E ORDINE DI FABBRICAZIONE (ODL) ---
		RIGHT OUTER JOIN dbo.DO33_DOCCORPORIF AS OC_DO33 WITH (NOLOCK)
			ON OC_C.DO30_NUMREG_CO99 = OC_DO33.DO33_NUMREGRIF_CO99 
			AND OC_C.DO30_PROGRIGA = OC_DO33.DO33_PROGRIGARIF_DO30 
			AND	OC_C.DO30_DITTA_CG18 = OC_DO33.DO33_DITTA_CG18 
			
		-- ==============================================================================================================
		-- Inizio Rev.1 (SOLVERIS - Bandera Marco)
		-- Modifica mantenuta per il blocco delle permutazioni errate
		-- ==============================================================================================================
				-- Vincolo salvavita introdotto in Rev.1: DO33_PROGRIF = 1 impedisce il prodotto cartesiano
		LEFT OUTER JOIN dbo.DO33_DOCCORPORIF AS OC_DO33_PROPRIO WITH (NOLOCK)
			ON  OC_C.DO30_DITTA_CG18 = OC_DO33_PROPRIO.DO33_DITTA_CG18 
			AND OC_C.DO30_NUMREG_CO99 = OC_DO33_PROPRIO.DO33_NUMREG_CO99 
			AND OC_C.DO30_PROGRIGA = OC_DO33_PROPRIO.DO33_PROGRIGA
			AND OC_DO33_PROPRIO.DO33_PROGRIF = 1

				-- --- AGGANCIO TESTATA E CORPO ORDINE DI LAVORO (ODL) ---
		-- La RIGHT OUTER JOIN con ON 1=1 funge da perno sintetico per preservare la struttura della query 
		-- e consentire il successivo INNER JOIN sulle righe del documento di produzione ODL.
		RIGHT OUTER JOIN dbo.DO11_DOCTESTATA AS ODL_T WITH (NOLOCK)
			ON 1=1 -- Necessario come placeholder per il successivo INNER JOIN dipendente
		INNER JOIN dbo.DO30_DOCCORPO AS ODL_C WITH (NOLOCK)
			ON ODL_T.DO11_DITTA_CG18 = ODL_C.DO30_DITTA_CG18 
			AND ODL_T.DO11_NUMREG_CO99 = ODL_C.DO30_NUMREG_CO99 
			AND OC_DO33.DO33_NUMREG_CO99 = ODL_C.DO30_NUMREG_CO99 
			AND OC_DO33.DO33_DITTA_CG18 = ODL_C.DO30_DITTA_CG18 
			AND OC_DO33.DO33_PROGRIGA = ODL_C.DO30_PROGRIGA 
			
		LEFT OUTER JOIN dbo.DO31_DOCCORPOORD AS DO31 WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = DO31.DO31_DITTA_CG18 
			AND OC_C.DO30_NUMREG_CO99 = DO31.DO31_NUMREG_CO99 
			AND	OC_C.DO30_PROGRIGA = DO31.DO31_PROGRIGA 
						 
		LEFT OUTER JOIN dbo.DO35_DOCCORPOPERS AS OC_DO35 WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = OC_DO35.DO35_DITTA_CG18 
			AND OC_C.DO30_NUMREG_CO99 = OC_DO35.DO35_NUMREG_CO99 
			AND	OC_C.DO30_PROGRIGA = OC_DO35.DO35_PROGRIGA
			AND ISNULL(OC_DO35.DO35_PROG,1) = 1
						 
		LEFT JOIN DO20_DOCTESTAEST AS OC_DO20 WITH (NOLOCK)
			ON OC_T.DO11_DITTA_CG18 = OC_DO20.DO20_DITTA_CG18
			AND	OC_T.DO11_NUMREG_CO99 = OC_DO20.DO20_NUMREG_CO99
			AND ISNULL(OC_DO20.DO20_PROG,1) = 1

		LEFT JOIN DO20_DOCTESTAEST AS ODL_DO20 WITH (NOLOCK)
			ON ODL_T.DO11_DITTA_CG18 = ODL_DO20.DO20_DITTA_CG18
			AND	ODL_T.DO11_NUMREG_CO99 = ODL_DO20.DO20_NUMREG_CO99
			AND ISNULL(ODL_DO20.DO20_PROG,1) = 1
			
		LEFT JOIN DO17_DOCTESTAPERS AS OC_DO17 WITH (NOLOCK)
			ON OC_T.DO11_DITTA_CG18 = OC_DO17.DO17_DITTA_CG18
			AND	OC_T.DO11_NUMREG_CO99 = OC_DO17.DO17_NUMREG_CO99
			AND ISNULL(OC_DO17.DO17_PROG,1) = 1

		LEFT JOIN DO36_DOCCORPOEST AS OC_DO36 WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = OC_DO36.DO36_DITTA_CG18
			AND	OC_C.DO30_NUMREG_CO99 = OC_DO36.DO36_NUMREG_CO99
			AND	OC_C.DO30_PROGRIGA = OC_DO36.DO36_PROGRIGA
			AND ISNULL(OC_DO36.DO36_PROG,1) = 1
			
		LEFT JOIN DO36_DOCCORPOEST AS ODL_DO36 WITH (NOLOCK)
			ON ODL_C.DO30_DITTA_CG18 = ODL_DO36.DO36_DITTA_CG18
			AND	ODL_C.DO30_NUMREG_CO99 = ODL_DO36.DO36_NUMREG_CO99
			AND	ODL_C.DO30_PROGRIGA = ODL_DO36.DO36_PROGRIGA
			AND ISNULL(ODL_DO36.DO36_PROG,1) = 1
						 
		LEFT JOIN DO12_DOCTESTARIF AS OC_DO12 WITH (NOLOCK)
			ON OC_T.DO11_DITTA_CG18 = OC_DO12.DO12_DITTA_CG18
			AND	OC_T.DO11_NUMREG_CO99 = OC_DO12.DO12_NUMREG_CO99
			AND	ISNULL(OC_DO12.DO12_PROGRIF,1) = 1

				-- --- DECODIFICA TABELLARE LAVORAZIONI EXTRA E CERTIFICATI TRAMITE DO05_ANAGCAMPIPERS ---
		-- DO04 = 52, 53, 54: Lavorazioni extra 1, 2, 3 impostate a livello di Testata OC (DO20)
		-- DO04 = 57, 58, 59: Lavorazioni extra 1, 2, 3 impostate a livello di Riga OC (DO36)
		-- DO04 = 21, 33:     Certificati di collaudo impostati su Testata OC (DO17) e Riga OC (DO35)
		-- DO04 = 52..59:     Lavorazioni extra impostate direttamente su Testata/Riga ODL
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 52) AS OC_EXTRA_LAV_TESTATA_1 ON OC_DO20.DO20_ALFST5 = OC_EXTRA_LAV_TESTATA_1.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 53) AS OC_EXTRA_LAV_TESTATA_2 ON OC_DO20.DO20_ALFST6 = OC_EXTRA_LAV_TESTATA_2.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 54) AS OC_EXTRA_LAV_TESTATA_3 ON OC_DO20.DO20_ALFST7 = OC_EXTRA_LAV_TESTATA_3.DO05_CODICE

		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 57) AS OC_EXTRA_LAV_RIGA_1 ON OC_DO36.DO36_ALFST5 = OC_EXTRA_LAV_RIGA_1.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 58) AS OC_EXTRA_LAV_RIGA_2 ON OC_DO36.DO36_ALFST6 = OC_EXTRA_LAV_RIGA_2.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 59) AS OC_EXTRA_LAV_RIGA_3 ON OC_DO36.DO36_ALFST7 = OC_EXTRA_LAV_RIGA_3.DO05_CODICE

		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 21) AS OC_CERT_TESTATA ON OC_DO17.DO17_INDPERS1  = OC_CERT_TESTATA.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 33) AS OC_CERT_RIGA ON OC_DO35.DO35_INDPERS1   = OC_CERT_RIGA.DO05_CODICE

		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 52) AS ODL_EXTRA_LAV_TESTATA_1 ON ODL_DO20.DO20_ALFST5 = ODL_EXTRA_LAV_TESTATA_1.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 53) AS ODL_EXTRA_LAV_TESTATA_2 ON ODL_DO20.DO20_ALFST6 = ODL_EXTRA_LAV_TESTATA_2.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 54) AS ODL_EXTRA_LAV_TESTATA_3 ON ODL_DO20.DO20_ALFST7 = ODL_EXTRA_LAV_TESTATA_3.DO05_CODICE

		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 57) AS ODL_EXTRA_LAV_RIGA_1 ON ODL_DO36.DO36_ALFST5 = ODL_EXTRA_LAV_RIGA_1.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 58) AS ODL_EXTRA_LAV_RIGA_2 ON ODL_DO36.DO36_ALFST6 = ODL_EXTRA_LAV_RIGA_2.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 59) AS ODL_EXTRA_LAV_RIGA_3 ON ODL_DO36.DO36_ALFST7 = ODL_EXTRA_LAV_RIGA_3.DO05_CODICE

		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 21) AS ODL_CERT_TESTATA ON OC_DO17.DO17_INDPERS1  = ODL_CERT_TESTATA.DO05_CODICE
		LEFT JOIN (SELECT DO05_CODICE, DO05_DESCRIZIONE FROM DO05_ANAGCAMPIPERS WITH (NOLOCK) WHERE DO05_IDDEFCAMPOPERS_DO04 = 33) AS ODL_CERT_RIGA ON OC_DO35.DO35_INDPERS1   = ODL_CERT_RIGA.DO05_CODICE

				-- --- CICLO DI PRODUZIONE E ATTRIBUTI CARTELLINO DI REPARTO ---
		-- Recupera il ciclo di fabbricazione collegato alla distinta base dell'ODL (PD48/PD52)
		-- e gli attributi descrittivi del cartellino (CO5L_ALF90)
		LEFT JOIN (SELECT DISTINCT PD48_IDDISBA_PD95, PD48_CICLO_PD52 FROM PD48_CICLI WITH (NOLOCK)) AS PD48_ODL_C ON ODL_C.DO30_IDDISBA_PD95 = PD48_ODL_C.PD48_IDDISBA_PD95
		LEFT JOIN PD52_ANAGCICLI AS PD52_ODL_C WITH (NOLOCK) ON PD48_ODL_C.PD48_CICLO_PD52 = PD52_ODL_C.PD52_CODICE
		LEFT JOIN CO5L_ATTRIBUTIDEN AS CO5L_OCL_C WITH (NOLOCK) ON PD52_ODL_C.PD52_GUID = CO5L_OCL_C.CO5L_GUID
		LEFT JOIN MG66_ANAGRART WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = MG66_ANAGRART.MG66_DITTA_CG18
			AND	OC_C.DO30_CODART_MG66 = MG66_ANAGRART.MG66_CODART

		LEFT JOIN CO5L_ATTRIBUTIDEN AS CO5L_ARTPF WITH (NOLOCK) ON MG66_ANAGRART.MG66_GUID = CO5L_ARTPF.CO5L_GUID
						 
		LEFT JOIN [dbo].[VPRT_DECODE_DO36_INDST1] AS TIPO_PRODUZIONE WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = TIPO_PRODUZIONE.[DO36_DITTA_CG18]
			AND	OC_C.DO30_NUMREG_CO99 = TIPO_PRODUZIONE.[DO36_NUMREG_CO99]
			AND	OC_C.DO30_PROGRIGA = TIPO_PRODUZIONE.[DO36_PROGRIGA]
			
		LEFT JOIN [dbo].[VPRT_CERT_HT_SIGLE_SUBSTITUTE] WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18	= [VPRT_CERT_HT_SIGLE_SUBSTITUTE].[DO30_DITTA_CG18]
			AND	OC_C.DO30_NUMREG_CO99 = [VPRT_CERT_HT_SIGLE_SUBSTITUTE].[DO30_NUMREG_CO99]
			AND	OC_C.DO30_PROGRIGA = [VPRT_CERT_HT_SIGLE_SUBSTITUTE].[DO30_PROGRIGA]
			
		LEFT JOIN MG7A_UBICAZARTFIX WITH (NOLOCK)
			ON OC_C.DO30_DITTA_CG18 = MG7A_DITTA_CG18
			AND	OC_C.DO30_CODART_MG66 = MG7A_CODART_MG66
			AND	OC_C.DO30_OPZIONE_MG5E = MG7A_OPZIONE_MG5E
			AND	OC_C.DO30_CODDEP_MG58 = MG7A_CODDEP_MG58
			
				-- --- DISTINTA BASE DI PRODUZIONE E LEGAMI COMPONENTI (MATERIA PRIMA) ---
		-- Aggancio alla distinta base master (PD95) e ai componenti di primo livello (PD96) per estrarre
		-- la barra / materia prima di partenza (PD96_COMPON, PD96_OPZIONE, coefficienti d'impiego)
		INNER JOIN PD95_DISBA WITH (NOLOCK)
			ON ODL_C.DO30_IDDISBA_PD95 = PD95_IDDISBA
		INNER JOIN PD96_LEGAMIDISBA WITH (NOLOCK)
			ON PD95_IDDISBA = PD96_IDDISBA_PD95

				-- --- MONITORAGGIO LOGISTICO A VALLE: PRE-DDT, PACKING LIST E BOLLE EFFETTIVE (DDT) ---
		-- Reperisce lo stato di avanzamento delle spedizioni collegando l'ordine cliente alle preparazioni
		-- di spedizione (DC-PREDDT), ai colli imballati (DC-PKL2) e ai DDT di vendita evasi (TipoDoc = 1).
		LEFT JOIN (
			SELECT PREDDT_T.DO11_DITTA_CG18, PREDDT_C.DO30_NUMREG_CO99, PREDDT_C.DO30_PROGRIGA, PREDDT_DO33.DO33_DITTA_CG18, PREDDT_DO33.DO33_NUMREGRIF_CO99, PREDDT_DO33.DO33_PROGRIGARIF_DO30, PREDDT_DO33.DO33_PROGRIF, PREDDT_C.DO30_QTA1
			FROM DO11_DOCTESTATA AS PREDDT_T WITH (NOLOCK)
			INNER JOIN DO30_DOCCORPO AS PREDDT_C WITH (NOLOCK) ON PREDDT_T.DO11_DITTA_CG18 = PREDDT_C.DO30_DITTA_CG18 AND PREDDT_T.DO11_NUMREG_CO99 = PREDDT_C.DO30_NUMREG_CO99
			INNER JOIN DO33_DOCCORPORIF AS PREDDT_DO33 WITH (NOLOCK) ON PREDDT_C.DO30_DITTA_CG18 = PREDDT_DO33.DO33_DITTA_CG18 AND PREDDT_C.DO30_NUMREG_CO99 = PREDDT_DO33.DO33_NUMREG_CO99 AND PREDDT_C.DO30_PROGRIGA = PREDDT_DO33.DO33_PROGRIGA
			WHERE PREDDT_T.DO11_DOCUM_MG36 = 'DC-PREDDT'
		) AS PREDDT
			ON OC_C.DO30_DITTA_CG18 = PREDDT.DO33_DITTA_CG18
			AND	OC_C.DO30_NUMREG_CO99 = PREDDT.DO33_NUMREGRIF_CO99
			AND	OC_C.DO30_PROGRIGA = PREDDT.DO33_PROGRIGARIF_DO30
			AND	1 = PREDDT.DO33_PROGRIF
			
		LEFT JOIN (
			SELECT PKL_T.DO11_DITTA_CG18, PKL_DO33.DO33_DITTA_CG18, PKL_DO33.DO33_NUMREGRIF_CO99, PKL_DO33.DO33_PROGRIGARIF_DO30, PKL_DO33.DO33_PROGRIF, PKL_C.DO30_QTA1
			FROM DO11_DOCTESTATA AS PKL_T WITH (NOLOCK)
			INNER JOIN DO30_DOCCORPO AS PKL_C WITH (NOLOCK) ON PKL_T.DO11_DITTA_CG18 = PKL_C.DO30_DITTA_CG18 AND PKL_T.DO11_NUMREG_CO99 = PKL_C.DO30_NUMREG_CO99
			INNER JOIN DO33_DOCCORPORIF AS PKL_DO33 WITH (NOLOCK) ON PKL_C.DO30_DITTA_CG18 = PKL_DO33.DO33_DITTA_CG18 AND PKL_C.DO30_NUMREG_CO99 = PKL_DO33.DO33_NUMREG_CO99 AND PKL_C.DO30_PROGRIGA = PKL_DO33.DO33_PROGRIGA
			WHERE PKL_T.DO11_DOCUM_MG36 = 'DC-PKL2'
		) AS PKL
			ON OC_C.DO30_DITTA_CG18	= PKL.DO33_DITTA_CG18
			AND	OC_C.DO30_NUMREG_CO99 = PKL.DO33_NUMREGRIF_CO99
			AND	OC_C.DO30_PROGRIGA = PKL.DO33_PROGRIGARIF_DO30
			AND	1 = PKL.DO33_PROGRIF
			
		LEFT JOIN (
			SELECT DDT_DO33.DO33_DITTA_CG18, DDT_DO33.DO33_NUMREGRIF_CO99, DDT_DO33.DO33_PROGRIGARIF_DO30, DDT_DO33.DO33_PROGRIF, DDT_C.DO30_QTA1, DDT_T.DO11_DATADOC
			FROM DO11_DOCTESTATA AS DDT_T WITH (NOLOCK)
			INNER JOIN DO30_DOCCORPO AS DDT_C WITH (NOLOCK) ON DDT_T.DO11_DITTA_CG18 = DDT_C.DO30_DITTA_CG18 AND DDT_T.DO11_NUMREG_CO99 = DDT_C.DO30_NUMREG_CO99
			INNER JOIN DO33_DOCCORPORIF AS DDT_DO33 WITH (NOLOCK) ON DDT_C.DO30_DITTA_CG18 = DDT_DO33.DO33_DITTA_CG18 AND DDT_C.DO30_NUMREG_CO99 = DDT_DO33.DO33_NUMREG_CO99 AND DDT_C.DO30_PROGRIGA = DDT_DO33.DO33_PROGRIGA
			WHERE DDT_T.DO11_TIPODOC = 1 AND DDT_T.DO11_TIPOCF_CG44 = 0 AND DDT_T.DO11_ANNODOC >= 2024
		) AS DDT
			ON PREDDT.DO11_DITTA_CG18 = DDT.DO33_DITTA_CG18 -- Ripristinata join per allineare scope
			AND	PREDDT.DO30_NUMREG_CO99 = DDT.DO33_NUMREGRIF_CO99
			AND	PREDDT.DO30_PROGRIGA = DDT.DO33_PROGRIGARIF_DO30
			AND	1 = DDT.DO33_PROGRIF	

		LEFT JOIN RT11_VOLUMI_ALTEZZE WITH (NOLOCK)
			ON SUBSTRING(OC_C.DO30_CODART_MG66,1,3) = RT11_TIPOLOGIA
			AND	SUBSTRING(OC_C.DO30_CODART_MG66,9,4) = RT11_DIAMETRO
			
		INNER JOIN CG44_CLIFOR AS OC_CLIFOR WITH (NOLOCK)
			ON OC_T.DO11_DITTACF_CG44 = OC_CLIFOR.CG44_DITTA_CG18	
			AND	OC_T.DO11_TIPOCF_CG44 = OC_CLIFOR.CG44_TIPOCF
			AND	OC_T.DO11_CLIFOR_CG44 = OC_CLIFOR.CG44_CLIFOR
			
		--LEFT JOIN (
		--	SELECT MG4G_DITTA_CG18, MG4G_CODART_MG66, MG4G_OPZIONE_MG5E, CO5L_ALF102
		--	FROM MG4G_ANAGRLOTTI WITH (NOLOCK)
		--	INNER JOIN CO5L_ATTRIBUTIDEN WITH (NOLOCK) ON MG4G_GUID = CO5L_GUID
		--	WHERE CO5L_ALF102 IS NOT NULL
		--) AS LOTTO_KB_EMERSON
		--	ON LOTTO_KB_EMERSON.MG4G_DITTA_CG18 = OC_T.DO11_DITTA_CG18
		--	AND	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'COMPON'),'') = LOTTO_KB_EMERSON.MG4G_CODART_MG66
		--	AND	ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'OPZIONE'),'') = LOTTO_KB_EMERSON.MG4G_OPZIONE_MG5E

		-- ==============================================================================================================
		-- SVILUPPO DELLE OUTER APPLY PER OTTIMIZZARE LE SUB-QUERY PRESENTI ORIGINARIAMENTE NELLA SELECT
		-- ==============================================================================================================

		-- ==============================================================================================================
		-- Inizio Rev.3 (SOLVERIS - Bandera Marco)
		-- Modifica per eliminare le permutazioni dei lotti. Utilizzato OUTER APPLY con TOP 1 e ORDER BY MG4G_DATACRE DESC
		-- per prelevare esclusivamente il lotto piÃ¹ recente, evitando di moltiplicare le righe del report.
		-- Tutti gli oggetti utilizzano hint WITH (NOLOCK) per non bloccare le letture.
		-- ==============================================================================================================
		OUTER APPLY (
			SELECT TOP 1 CO5L.CO5L_ALF102
			FROM MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK)
			INNER JOIN CO5L_ATTRIBUTIDEN AS CO5L WITH (NOLOCK) 
				ON MG4G.MG4G_GUID = CO5L.CO5L_GUID
			WHERE MG4G.MG4G_DITTA_CG18 = 1
			  AND MG4G.MG4G_CODART_MG66 = ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'COMPON'),'')
			  AND MG4G.MG4G_OPZIONE_MG5E = ISNULL([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95,'OPZIONE'),'')
			  AND CO5L.CO5L_ALF102 IS NOT NULL
			ORDER BY MG4G.MG4G_DATACRE DESC
		) AS LOTTO_KB_EMERSON

		--OUTER APPLY (
		--	SELECT TOP 1 CO5L_ALF102
		--		FROM (
		--		SELECT  TOP 1 CO5L.CO5L_ALF102 ,1 AS RANKING ,MG4G_DATACRE
		--					FROM MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK)
		--					INNER JOIN CO5L_ATTRIBUTIDEN AS CO5L WITH (NOLOCK) 
		--						ON MG4G.MG4G_GUID = CO5L.CO5L_GUID
		--					WHERE MG4G.MG4G_DITTA_CG18 = 1
		--					  AND MG4G.MG4G_CODART_MG66 = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'COMPON'),'')
		--					  AND MG4G.MG4G_OPZIONE_MG5E = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'OPZIONE'),'')
		--					  AND MG4G.MG4G_CODLOTTO = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'LOTTO'),'')
		--					  AND CO5L.CO5L_ALF102 IS NOT NULL
		--					--ORDER BY MG4G.MG4G_DATACRE DESC

		--		UNION 

		--			SELECT TOP 1 CO5L.CO5L_ALF102 ,2 AS RANKING, MG4G_DATACRE 
		--					FROM MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK)
		--					INNER JOIN CO5L_ATTRIBUTIDEN AS CO5L WITH (NOLOCK) 
		--						ON MG4G.MG4G_GUID = CO5L.CO5L_GUID
		--					WHERE MG4G.MG4G_DITTA_CG18 = 1
		--					  AND MG4G.MG4G_CODART_MG66 = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'COMPON'),'')
		--					  AND MG4G.MG4G_OPZIONE_MG5E = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'OPZIONE'),'')
		--					  --AND MG4G.MG4G_CODLOTTO = ISNULL([dbo].[SPRT_LTT_FAKE](4851918,'LOTTO'),'')
		--					  AND CO5L.CO5L_ALF102 IS NOT NULL

		--		ORDER BY RANKING ASC, MG4G_DATACRE DESC
		--		) AS LOTTO_KB_EMERSON_SUBSELECT
		--		) AS LOTTO_KB_EMERSON

		OUTER APPLY (
			SELECT TOP 1  
				
				CASE
				WHEN ISNUMERIC(SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,4,2)) = 1 
							/* BM 2026/04/15 - Esclusione degli articoli in HGE nel calcolo della minorazione*/
							and SUBSTRING(DO30_CICLI_FASE1400.DO30_OPZIONE_MG5E,6,3) <> 'HGE'
							/*****/
							THEN 'Ø medio ' + FORMAT(RT05_DIAMETRO - (CONVERT(decimal(4,2),replace(SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,4,2),'--','00'))/10),'##0.00') + ' mm +0 / -0,05'
							ELSE --'0'	
									(
										iif (CONVERT(decimal(4,2),replace(SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,4,2),'--','00')) = 4
											,'Ø medio ' + FORMAT(RT05_DIAMETRO ,'##0.00') + ' mm +0 / -0,05'
											,'Ø medio ' + FORMAT(RT05_DIAMETRO - (CONVERT(decimal(4,2),replace(SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,4,2),'--','00'))/10),'##0.00') + ' mm +0 / -0,05'
											)
										 
									)
						END 
						AS DIAMETRO_MEDIO
				
			FROM PD48_CICLI AS PD48_CICLI_FASE1400 WITH (NOLOCK)
			INNER JOIN DO30_DOCCORPO AS DO30_CICLI_FASE1400 WITH (NOLOCK) 
				ON PD48_CICLI_FASE1400.PD48_IDDISBA_PD95 = DO30_CICLI_FASE1400.DO30_IDDISBA_PD95
			INNER JOIN RT05_DESCR_DIAM_PASSO WITH (NOLOCK) 
				ON SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,9,4) = RT05_SUBCODICE_MG6E_1 
				AND SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,13,2) = RT05_SUBCODICE_MG6E_2
			WHERE PD48_CICLI_FASE1400.PD48_IDDISBA_PD95 = ODL_C.DO30_IDDISBA_PD95
			  AND PD48_CICLI_FASE1400.PD48_CODFASE_PD12 IN (1400,1401,1402,1404,1405,1406,1407,1410,1415,1417,1418,1419,1420,1423,1424,1426,1472,1900)
			  AND ISNUMERIC(replace(SUBSTRING(DO30_CICLI_FASE1400.DO30_CODART_MG66,4,2),'--','00')) = 1 
		) AS OA_DIAMETRO



		OUTER APPLY (
			SELECT TOP 1 ISNULL(RT03_MARKING,'') AS MARKING
			FROM PD48_CICLI AS PD48_CICLI_FASETIMBRA WITH (NOLOCK)
			INNER JOIN DO30_DOCCORPO AS DO30_CICLI_FASETIMBRA WITH (NOLOCK) 
				ON PD48_CICLI_FASETIMBRA.PD48_IDDISBA_PD95 = DO30_CICLI_FASETIMBRA.DO30_IDDISBA_PD95
			INNER JOIN RT03_DESCRALTER WITH (NOLOCK) 
				ON SUBSTRING(DO30_CICLI_FASETIMBRA.DO30_CODART_MG66,6,3) = RT03_SUBCODICE_MG6E 
				AND RT03_PROGR_MG6E = 3   
				AND RT03_PROGR = 0   
				AND RT03_DITTA_CG18 = ODL_C.DO30_DITTA_CG18
			WHERE PD48_CICLI_FASETIMBRA.PD48_IDDISBA_PD95 = ODL_C.DO30_IDDISBA_PD95
			  AND PD48_CICLI_FASETIMBRA.PD48_CODFASE_PD12 IN (1250,1270,1271)
		) AS OA_MARKING

		OUTER APPLY (
			SELECT MAX(PD48_SEQFASE) AS SequenzaFaseCutOffStampaBarcode 
			FROM PD48_CICLI WITH (NOLOCK)
			WHERE PD48_CODFASE_PD12 >= 4020 AND PD48_CODFASE_PD12 <= 4029
			  AND PD48_IDDISBA_PD95 = ODL_C.DO30_IDDISBA_PD95
		) AS OA_SEQ_BARCODE
		
		OUTER APPLY (
			SELECT TOP 1 PD48_NOTA AS PD48_NOTA_MARCATURA
			FROM PD48_CICLI WITH (NOLOCK)
			WHERE PD48_IDDISBA_PD95 = ODL_C.DO30_IDDISBA_PD95 
			  AND PD48_CODFASE_PD12 IN (SELECT IE29_VALINTERNO FROM IE29_TRASCODIFVAL WITH (NOLOCK) WHERE IE29_CODTRASC_IE28 = 'TMV-EXLAV-MAR')
		) AS OA_NOTA_MARC

/* ==============================================================================================================
   SEZIONE 7: CONDIZIONI DI FILTRO FINALI (WHERE CLAUSE)
   --------------------------------------------------------------------------------------------------------------
   - ODL_T.DO11_TIPODOC = 24: Limita la selezione esclusivamente agli Ordini di Fabbricazione / Lavoro (ODL).
   - ODL_T.DO11_STIPODOC = 20: Seleziona il sotto-tipo specifico degli ODL standard di produzione interna TMV.
   - OC_T.DO11_TIPODOC = 21 OR OC_T.DO11_TIPODOC IS NULL: Considera unicamente gli Ordini Cliente confermati 
     (TipoDoc = 21), consentendo al contempo l'emissione del report per ODL interni di magazzino privi di OC abbinato.
   ============================================================================================================== */
WHERE (ODL_T.DO11_TIPODOC = 24) 
  AND (ODL_T.DO11_STIPODOC = 20) 
  AND (OC_T.DO11_TIPODOC = 21 OR OC_T.DO11_TIPODOC IS NULL)


