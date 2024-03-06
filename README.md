Pulmonary function test (PFT) results appear in mostly unstructured or semi-structured text data in the VA Corporate Data Warehouse (CDW). To capture PFT results for a study on long-acting controller inhalers in a veteran population, we generated regular expression-based text processing code to extract pre-bronchodilator values of FEV1:FVC ratio, FEV1 percent of predicted value, and qualitative data describing spriometry results. These algorithms were generated on a facility-specific basis, so each file in this repository extracts data from a separate facility.

The general approach is as follows:
\n
-Identify PFTs procedures completed for your cohort
\n
-Collate all TIU Notes from -1 through +21 days relative to the procedure
\n
-Import the data into Python
\n
-Identify templated notes, i.e. notes with a common phrase denoting the beginning of spirometry results or PFT interpretation
\n
-Create note snippets based on the template start phrase, excluding all text outside of a certain character range relative to the snippet start phrase
\n
-Use regular expressions to extract values from your variable(s) of interest
\n
-Map extracted values to categories defined by the 2005 American Thoracic Society/European Respiratory Society (ATS/ERS) PFT interpretation guidelines
\n
-Export the new dataset as an Excel file for validation

You may alter the regular expressions provided in these files to fit your specific research questions in terms of which variables you'd like to extract from PFT notes.
