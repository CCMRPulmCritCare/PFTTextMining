--Pull outpat and inpat pfts performed for our cohort patients during SWITCH period
DROP TABLE IF EXISTS #pfts
--Outpatient PFTs
SELECT DISTINCT
	COH.PatientICN
	,COH.PatientSID
	,CAST(pft.VProcedureDateTime AS DATE) AS pft_date
	,CASE
		WHEN Inst.InstitutionSID > 0 THEN CONCAT('(', Inst.InstitutionCode, ') ', Inst.InstitutionName)
		WHEN Inst2.InstitutionSID > 0 THEN CONCAT('(', Inst2.InstitutionCode, ') ', Inst2.InstitutionName)
		WHEN D.DivisionSID > 0 THEN CONCAT('(', D.Sta6a, ') ', D.DivisionName)
		WHEN D2.DivisionSID > 0 THEN CONCAT('(', D2.Sta6a, ') ', D2.DivisionName)
		ELSE 'Unavailable'
		END AS facility_name
	,D.Sta6a
	,'Outpat' AS VisitType
INTO #pfts
FROM
	dflt.sids AS COH
INNER JOIN
	Src.Outpat_Workload AS V
	ON	 COH.PatientSID = V.PatientSID
INNER JOIN
	CDWWork.Dim.Location AS L
	ON		V.LocationSID = L.LocationSID
INNER JOIN
	CDWWork.Dim.Institution AS Inst
	ON		L.InstitutionSID = Inst.InstitutionSID
INNER JOIN
	CDWWork.Dim.Institution AS Inst2
	ON		V.InstitutionSID = Inst2.InstitutionSID
INNER JOIN
	CDWWork.Dim.Division AS D
	ON		V.DivisionSID = D.DivisionSID
INNER JOIN
	CDWWork.Dim.Division AS D2
	ON		V.DivisionSID = D2.DivisionSID
INNER JOIN Src.Outpat_WorkloadVProcedure pft
	ON		V.VisitSID = pft.VisitSID
INNER JOIN CDWWork.Dim.CPT cpt
	ON		pft.CPTSID = cpt.CPTSID
WHERE 
	(pft.VProcedureDateTime >= '2018-01-01' and pft.VProcedureDateTime <= '2022-12-31')
	AND cpt.CPTCode in ('94010', '94375', '94060', '94726', '94727', '94729', '94150')

UNION

--Inpatient PFTs
SELECT DISTINCT
	COH.PatientICN
	,COH.PatientSID
	,CASE
		WHEN I.DischargeDateTime <= '12-31-2022' THEN
		CAST(I.DischargeDateTime AS DATE)
		ELSE CAST(I.AdmitDateTime AS DATE)
		END AS pft_date
	,CASE
		WHEN Inst.InstitutionSID > 0 THEN CONCAT('(', Inst.InstitutionCode, ') ', Inst.InstitutionName)
		WHEN D.DivisionSID > 0 THEN CONCAT('(', D.Sta6a, ') ', D.DivisionName)
		ELSE 'Unavailable'
		END AS facility_name
	,'Inpat' AS VisitType
	,D.Sta6a
FROM
	dflt.sids AS COH
INNER JOIN
	Src.Inpat_Inpatient AS I
	ON		COH.PatientSID = I.PatientSID
LEFT JOIN
	CDWWork.Dim.WardLocation AS WL
	ON		WL.WardLocationSID = I.AdmitWardLocationSID
LEFT JOIN
	CDWWork.Dim.Location AS L
	ON		L.LocationSID = WL.LocationSID
LEFT JOIN
	CDWWork.Dim.Institution AS Inst
	ON		L.InstitutionSID = Inst.InstitutionSID
LEFT JOIN
	CDWWork.Dim.Division AS D
	ON		WL.DivisionSID = D.DivisionSID
INNER JOIN Src.Inpat_InpatientCPTProcedure pft
	ON pft.InpatientSID = I.InpatientSID AND pft.AdmitDateTime = I.AdmitDateTime
INNER JOIN CDWWork.Dim.CPT cpt
	ON cpt.CPTSID = pft.CPTSID
WHERE
	(I.DischargeDateTime >= '01-01-2018' AND I.DischargeDateTime <= '12-31-2022')
	AND (I.AdmitDateTime >= '01-01-2018' AND I.AdmitDateTime <= '12-31-2022')
	AND cpt.CPTCode in ('94010', '94375', '94060','94726','94727','94729', '94150');


--Pull FEV1 values for PFTs that have result data in CDW-Raw
DROP TABLE IF EXISTS #cdw_raw_fev
SELECT DISTINCT
	pft.PatientICN
	,pft.PatientSID
	,fev.FEV1
	,fev.FlowsStudy
	,ids.Datetime AS pft_date
INTO
	#cdw_raw_fev
FROM Src.PFT_pulmonaryx_flows_study_700_018 AS fev
INNER JOIN Src.PFT_pulmonary_function_tests_700 AS ids
	ON fev.PulmonaryFunctionTestsIEN = ids.PulmonaryFunctionTestsIEN AND fev.Sta3n = ids.Sta3n
INNER JOIN #pfts AS pft
	ON ids.PatientSID = pft.PatientSID AND CAST(ids.DATETIME AS DATE) = pft.pft_date
WHERE fev.FEV1 IS NOT NULL;


--Merge FEV1 data from CDW-Raw back into full dataset of PFT tests
DROP TABLE IF EXISTS #pft_pre_tiu
SELECT DISTINCT 
	pft.*
	,fevraw.FEV1
	,fevraw.FlowsStudy
INTO #pft_pre_tiu
FROM #pfts pft
LEFT JOIN #cdw_raw_fev fevraw
	ON pft.PatientSID = fevraw.PatientSID and pft.pft_date = CAST(fevraw.pft_date AS DATE);

--Pull all notes -1 to +21 days of PFT missing structured FEV1 data from CDW-Raw. Optional: include note dates
DROP TABLE IF EXISTS dflt.pft_with_tiu_21days
SELECT DISTINCT 
	pft.*
	--,CAST(notes.EntryDateTime AS DATE) AS note_date 
	,notes.ReportText
INTO dflt.pft_with_tiu_21days
FROM #pft_pre_tiu pft
INNER JOIN dflt.sids sids --dflt.sids contains all PatientSIDs and PatientICNs for our cohort. 
	ON pft.PatientICN = sids.PatientICN
INNER JOIN Src.STIUNotes_TIUDocument_8925 notes
	ON notes.PatientSID = sids.PatientSID
WHERE
	CAST(notes.EntryDateTime AS DATE) BETWEEN DATEADD(DAY, -1, pft.pft_date) AND DATEADD(DAY, 21, pft.pft_date)
	AND pft.FEV1 IS NULL;

--Make new table that keeps only notes with the string "FEV1" or its variations in the ntoe
DROP TABLE IF EXISTS dflt.notes_with_fev_21days
SELECT *
INTO dflt.notes_with_fev_21days
FROM dflt.pft_with_tiu_21days
WHERE
	LOWER(ReportText) LIKE '%fev1%' OR
	LOWER(ReportText) LIKE '%fev_1%' OR
	LOWER(ReportText) LIKE '%fev-1%' OR
	LOWER(ReportText) LIKE '%fev 1%' OR
	LOWER(ReportText) LIKE '%fev1[_]%';

/*
Query all notes from specific facilities using dflt.pft_with_tiu_21days and "sta6a = xxx" in the WHERE clause. 
You can use dflt.notes_with_fev_21days to calculate the proportion of notes from each facility with reference to
an FEV1 value using the below code:
*/

--Count of PFTs performed by sta6a with count of PFTs containing FEV1 values in TIU Notes
WITH DistinctPFTs AS (
	SELECT t1.Sta6a, t1.PatientICN, t1.pft_date
	FROM dflt.pft_with_tiu_21days t1
	GROUP BY t1.Sta6a, t1.PatientICN, t1.pft_date
),
NotesWithFEV1 AS (
	SELECT t2.Sta6a, t2.PatientICN, t2.pft_date
	FROM dflt.notes_with_fev_21days t2
	GROUP BY t2.Sta6a, t2.PatientICN, t2.pft_date
)
SELECT
	d.Sta6a,
	COUNT(*) AS TotalPFTs,
	(SELECT COUNT(*) FROM NotesWithFEV1 n WHERE n.Sta6a = d.Sta6a) AS PFTsWithFEV1,
	ROUND(CAST((SELECT COUNT(*) FROM NotesWithFEV1 n WHERE n.sta6a = d.sta6a) AS FLOAT) / COUNT(*) * 100, 2) AS percentage
FROM DistinctPFTs d
LEFT JOIN NotesWithFEV1 n
	ON d.Sta6a = n.Sta6a AND d.PatientICN = n.PatientICN AND d.pft_date = n.pft_date
GROUP BY d.Sta6a
ORDER by TotalPFTs desc;
