# Fixture resource file — deliberately NEVER read in the synthetic transcript

The synthetic transcript's only Read of this path happens on a sidechain
(isSidechain: true) line, which the correlator must exclude. The correlator
must classify this file as "never read".
