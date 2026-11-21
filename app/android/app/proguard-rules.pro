# PDF-Import (read_pdf_text → PDFBox-Android). Der JPEG2000-Decoder ist optional und fehlt absichtlich.
-dontwarn com.gemalto.jp2.JP2Decoder
# PDFBox lädt Schriften/Kodierungen teils per Reflexion – nicht wegkürzen.
-keep class com.tom_roush.** { *; }
-dontwarn com.tom_roush.**
