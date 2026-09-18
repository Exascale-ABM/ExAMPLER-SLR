# src

This folder contains the two main scripts used for the ExAMPLER Systematic Literature Review to extract BibTeX data downloaded from [Scopus](https://www.scopus.com/) and [Web of Science](https://www.webofscience.com/).

The `img` directory contains an icon for the [ExAMPLER](https://exascale.hutton.ac.uk/) project.

The `src` directory contains the [Perl](https://www.perl.org/) scripts and supporting modules in `lib`:

  + `slr-db-merge.pl` -- Merges BibTeX exports from Scopus and Web of Science into a single BibTeX file.
  + `slr-results.pl` -- Processes the merged BibTeX file with supporting results data (those we can include are in the `data` folder above) and generates tables and figures for use in an article.

The `lib` directory contains some Perl modules of which some may be useful in other contexts:

  + `BibTeX.pm` -- Various utility procedures for extracting data from BibTeX records.
  + `Convert.pm` -- Some utility procedures trying to manage different text file formats.
  + `Latin.pm` -- Utility procedures trying to remove accents from UTF-8 text.
  + `TextTK.pm` -- Procedures for processing text.
  + `WoS.pm` -- Procedures for managing Web of Science categories that formed part of the selection process.
