# Grader 1.3.2 vs the blind judge

1903 items sampled, 1903 judged; seed 20261021; 2000 bootstrap resamples. The grader stays the primary; the corrected figures are sensitivities.

- strict: agreement 0.6118 unweighted, 0.4611 weighted; kappa 0.2188 [0.1761, 0.2610]
- lenient: agreement 0.7249 unweighted, 0.5916 weighted; kappa 0.3133 [0.2637, 0.3614]

## Per stratum

| stratum | N | n | judged | agreement strict | lenient | confusion |
|---|---|---|---|---|---|---|
| a0_bare_fable_matched|review-r11|credited | 4 | 4 | 4 | 0.0000 | 0.2500 | grader_credit: does-not-describe 3, partially 1 |
| a0_bare_fable_matched|review-r11|far-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a0_bare_fable_matched|review-r11|near-miss | 5 | 5 | 5 | 0.8000 | 1.0000 | grader_no_credit: does-not-describe 4, partially 1 |
| a0_bare_fable_matched|review-r11|stray | 37 | 10 | 10 | — | — | grader_no_credit: real 2, wrong 8 |
| a0_bare_fable_matched|review-r14|credited | 11 | 10 | 10 | 0.0000 | 0.1000 | grader_credit: does-not-describe 9, partially 1 |
| a0_bare_fable_matched|review-r14|far-miss | 14 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r14|near-miss | 3 | 3 | 3 | 0.6667 | 0.6667 | grader_no_credit: describes 1, does-not-describe 2 |
| a0_bare_fable_matched|review-r14|stray | 31 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 3, style 2, wrong 2 |
| a0_bare_fable_matched|review-r15|credited | 44 | 10 | 10 | 0.1000 | 0.3000 | grader_credit: describes 1, does-not-describe 7, partially 2 |
| a0_bare_fable_matched|review-r15|far-miss | 52 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r15|near-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a0_bare_fable_matched|review-r15|stray | 32 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 5, wrong 2 |
| a0_bare_fable_matched|review-r16|credited | 2 | 2 | 2 | 0.0000 | 0.0000 | grader_credit: does-not-describe 2 |
| a0_bare_fable_matched|review-r16|far-miss | 9 | 9 | 9 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 9 |
| a0_bare_fable_matched|review-r16|near-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a0_bare_fable_matched|review-r16|stray | 50 | 10 | 10 | — | — | grader_no_credit: real 3, wrong 7 |
| a0_bare_fable_matched|review-r19|credited | 3 | 3 | 3 | 0.0000 | 0.0000 | grader_credit: does-not-describe 3 |
| a0_bare_fable_matched|review-r19|far-miss | 24 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r19|near-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a0_bare_fable_matched|review-r19|stray | 24 | 10 | 10 | — | — | grader_no_credit: real 3, style 1, wrong 6 |
| a0_bare_fable_matched|review-r20|credited | 2 | 2 | 2 | 0.0000 | 0.0000 | grader_credit: does-not-describe 2 |
| a0_bare_fable_matched|review-r20|far-miss | 17 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r20|near-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a0_bare_fable_matched|review-r20|stray | 39 | 10 | 10 | — | — | grader_no_credit: real 5, wrong 5 |
| a0_bare_fable_matched|review-r21|credited | 14 | 10 | 10 | 0.2000 | 0.4000 | grader_credit: describes 2, does-not-describe 6, partially 2 |
| a0_bare_fable_matched|review-r21|far-miss | 19 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r21|near-miss | 3 | 3 | 3 | 0.6667 | 0.6667 | grader_no_credit: describes 1, does-not-describe 2 |
| a0_bare_fable_matched|review-r21|stray | 28 | 10 | 10 | — | — | grader_no_credit: real 6, wrong 4 |
| a0_bare_fable_matched|review-r22|credited | 9 | 9 | 9 | 0.0000 | 0.0000 | grader_credit: does-not-describe 9 |
| a0_bare_fable_matched|review-r22|far-miss | 27 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r22|near-miss | 6 | 6 | 6 | 0.8333 | 0.8333 | grader_no_credit: describes 1, does-not-describe 5 |
| a0_bare_fable_matched|review-r22|stray | 27 | 10 | 10 | — | — | grader_no_credit: real 5, wrong 5 |
| a0_bare_fable_matched|review-r23|credited | 4 | 4 | 4 | 0.0000 | 0.5000 | grader_credit: does-not-describe 2, partially 2 |
| a0_bare_fable_matched|review-r23|far-miss | 19 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r23|near-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a0_bare_fable_matched|review-r23|stray | 30 | 10 | 10 | — | — | grader_no_credit: real 6, wrong 4 |
| a0_bare_fable_matched|review-r24|credited | 19 | 10 | 10 | 0.2000 | 0.4000 | grader_credit: describes 2, does-not-describe 6, partially 2 |
| a0_bare_fable_matched|review-r24|far-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a0_bare_fable_matched|review-r24|near-miss | 5 | 5 | 5 | 0.2000 | 0.6000 | grader_no_credit: describes 2, does-not-describe 1, partially 2 |
| a0_bare_fable_matched|review-r24|stray | 17 | 10 | 10 | — | — | grader_no_credit: real 3, wrong 7 |
| a0_bare_fable_matched|review-r25|credited | 12 | 10 | 10 | 0.2000 | 0.9000 | grader_credit: describes 2, does-not-describe 1, partially 7 |
| a0_bare_fable_matched|review-r25|far-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a0_bare_fable_matched|review-r25|near-miss | 3 | 3 | 3 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 3 |
| a0_bare_fable_matched|review-r25|stray | 11 | 10 | 10 | — | — | grader_no_credit: real 4, wrong 6 |
| a0_bare_fable_matched|review-r26|credited | 10 | 10 | 10 | 0.5000 | 0.9000 | grader_credit: describes 5, does-not-describe 1, partially 4 |
| a0_bare_fable_matched|review-r26|far-miss | 10 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a0_bare_fable_matched|review-r26|near-miss | 4 | 4 | 4 | 0.5000 | 1.0000 | grader_no_credit: does-not-describe 2, partially 2 |
| a0_bare_fable_matched|review-r26|stray | 12 | 10 | 10 | — | — | grader_no_credit: real 3, style 2, wrong 5 |
| a0_bare_fable_matched|review-r27|credited | 8 | 8 | 8 | 0.3750 | 0.5000 | grader_credit: describes 3, does-not-describe 4, partially 1 |
| a0_bare_fable_matched|review-r27|far-miss | 17 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_fable_matched|review-r27|stray | 16 | 10 | 10 | — | — | grader_no_credit: real 5, wrong 5 |
| a0_bare_fable_matched|review-r28|credited | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_credit: describes 2 |
| a0_bare_fable_matched|review-r28|far-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a0_bare_fable_matched|review-r28|stray | 34 | 10 | 10 | — | — | grader_no_credit: real 6, wrong 4 |
| a0_bare_matched|review-r11|credited | 12 | 10 | 10 | 0.5000 | 0.6000 | grader_credit: describes 5, does-not-describe 4, partially 1 |
| a0_bare_matched|review-r11|far-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a0_bare_matched|review-r11|near-miss | 9 | 9 | 9 | 0.5556 | 0.7778 | grader_no_credit: describes 2, does-not-describe 5, partially 2 |
| a0_bare_matched|review-r11|stray | 99 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 3, wrong 6 |
| a0_bare_matched|review-r14|credited | 33 | 10 | 10 | 0.2000 | 0.2000 | grader_credit: describes 2, does-not-describe 8 |
| a0_bare_matched|review-r14|far-miss | 11 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r14|near-miss | 8 | 8 | 8 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 8 |
| a0_bare_matched|review-r14|stray | 141 | 10 | 10 | — | — | grader_no_credit: not-a-finding 4, real 2, wrong 4 |
| a0_bare_matched|review-r15|credited | 90 | 10 | 10 | 0.1000 | 0.2000 | grader_credit: describes 1, does-not-describe 8, partially 1 |
| a0_bare_matched|review-r15|far-miss | 41 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r15|near-miss | 13 | 10 | 10 | 0.6000 | 1.0000 | grader_no_credit: does-not-describe 6, partially 4 |
| a0_bare_matched|review-r15|stray | 76 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 5, wrong 4 |
| a0_bare_matched|review-r16|credited | 16 | 10 | 10 | 0.1000 | 0.2000 | grader_credit: describes 1, does-not-describe 8, partially 1 |
| a0_bare_matched|review-r16|far-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a0_bare_matched|review-r16|near-miss | 12 | 10 | 10 | 0.5000 | 0.8000 | grader_no_credit: describes 2, does-not-describe 5, partially 3 |
| a0_bare_matched|review-r16|stray | 158 | 10 | 10 | — | — | grader_no_credit: real 9, wrong 1 |
| a0_bare_matched|review-r19|credited | 18 | 10 | 10 | 0.1000 | 0.2000 | grader_credit: describes 1, does-not-describe 8, partially 1 |
| a0_bare_matched|review-r19|far-miss | 11 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r19|near-miss | 24 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r19|stray | 156 | 10 | 10 | — | — | grader_no_credit: real 4, wrong 6 |
| a0_bare_matched|review-r20|credited | 4 | 4 | 4 | 0.0000 | 0.0000 | grader_credit: does-not-describe 4 |
| a0_bare_matched|review-r20|far-miss | 6 | 6 | 6 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 6 |
| a0_bare_matched|review-r20|near-miss | 3 | 3 | 3 | 0.6667 | 1.0000 | grader_no_credit: does-not-describe 2, partially 1 |
| a0_bare_matched|review-r20|stray | 57 | 10 | 10 | — | — | grader_no_credit: not-a-finding 2, real 3, wrong 5 |
| a0_bare_matched|review-r21|credited | 32 | 10 | 10 | 0.1000 | 0.4000 | grader_credit: describes 1, does-not-describe 6, partially 3 |
| a0_bare_matched|review-r21|far-miss | 14 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r21|near-miss | 12 | 10 | 10 | 0.6000 | 0.8000 | grader_no_credit: describes 2, does-not-describe 6, partially 2 |
| a0_bare_matched|review-r21|stray | 110 | 10 | 10 | — | — | grader_no_credit: real 4, wrong 6 |
| a0_bare_matched|review-r23|credited | 12 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a0_bare_matched|review-r23|far-miss | 14 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r23|near-miss | 6 | 6 | 6 | 0.8333 | 1.0000 | grader_no_credit: does-not-describe 5, partially 1 |
| a0_bare_matched|review-r23|stray | 78 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 4, wrong 3 |
| a0_bare_matched|review-r24|credited | 35 | 10 | 10 | 0.3000 | 0.3000 | grader_credit: describes 3, does-not-describe 7 |
| a0_bare_matched|review-r24|near-miss | 12 | 10 | 10 | 0.6000 | 0.6000 | grader_no_credit: describes 4, does-not-describe 6 |
| a0_bare_matched|review-r24|stray | 112 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 1, wrong 8 |
| a0_bare_matched|review-r25|credited | 34 | 10 | 10 | 0.5000 | 0.6000 | grader_credit: describes 5, does-not-describe 4, partially 1 |
| a0_bare_matched|review-r25|near-miss | 11 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a0_bare_matched|review-r25|stray | 51 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 3, wrong 6 |
| a0_bare_matched|review-r26|credited | 63 | 10 | 10 | 0.3000 | 0.5000 | grader_credit: describes 3, does-not-describe 5, partially 2 |
| a0_bare_matched|review-r26|far-miss | 5 | 5 | 5 | 0.8000 | 1.0000 | grader_no_credit: does-not-describe 4, partially 1 |
| a0_bare_matched|review-r26|near-miss | 7 | 7 | 7 | 0.7143 | 1.0000 | grader_no_credit: does-not-describe 5, partially 2 |
| a0_bare_matched|review-r26|stray | 44 | 10 | 10 | — | — | grader_no_credit: real 5, wrong 5 |
| a0_bare_matched|review-r27|credited | 28 | 10 | 10 | 0.3000 | 0.5000 | grader_credit: describes 3, does-not-describe 5, partially 2 |
| a0_bare_matched|review-r27|far-miss | 7 | 7 | 7 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 7 |
| a0_bare_matched|review-r27|near-miss | 9 | 9 | 9 | 0.8889 | 0.8889 | grader_no_credit: describes 1, does-not-describe 8 |
| a0_bare_matched|review-r27|stray | 99 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 4, wrong 5 |
| a0_bare_matched|review-r28|credited | 17 | 10 | 10 | 0.5000 | 0.7000 | grader_credit: describes 5, does-not-describe 3, partially 2 |
| a0_bare_matched|review-r28|near-miss | 2 | 2 | 2 | 0.5000 | 1.0000 | grader_no_credit: does-not-describe 1, partially 1 |
| a0_bare_matched|review-r28|stray | 85 | 10 | 10 | — | — | grader_no_credit: real 5, wrong 5 |
| a1_full_openmount|review-r11|credited | 40 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a1_full_openmount|review-r11|near-miss | 20 | 10 | 10 | 0.7000 | 0.8000 | grader_no_credit: describes 2, does-not-describe 7, partially 1 |
| a1_full_openmount|review-r11|stray | 144 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 6, wrong 3 |
| a1_full_openmount|review-r14|credited | 49 | 10 | 10 | 0.3000 | 0.3000 | grader_credit: describes 3, does-not-describe 7 |
| a1_full_openmount|review-r14|far-miss | 8 | 8 | 8 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 8 |
| a1_full_openmount|review-r14|near-miss | 23 | 10 | 10 | 0.8000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 8, partially 1 |
| a1_full_openmount|review-r14|stray | 101 | 10 | 10 | — | — | grader_no_credit: not-a-finding 8, wrong 2 |
| a1_full_openmount|review-r15|credited | 138 | 10 | 10 | 0.0000 | 0.5000 | grader_credit: does-not-describe 5, partially 5 |
| a1_full_openmount|review-r15|far-miss | 28 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full_openmount|review-r15|near-miss | 26 | 10 | 10 | 0.8000 | 1.0000 | grader_no_credit: does-not-describe 8, partially 2 |
| a1_full_openmount|review-r15|stray | 83 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 6, wrong 1 |
| a1_full_openmount|review-r16|credited | 32 | 10 | 10 | 0.3000 | 0.4000 | grader_credit: describes 3, does-not-describe 6, partially 1 |
| a1_full_openmount|review-r16|far-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_full_openmount|review-r16|near-miss | 25 | 10 | 10 | 0.7000 | 1.0000 | grader_no_credit: does-not-describe 7, partially 3 |
| a1_full_openmount|review-r16|stray | 224 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 2, wrong 2 |
| a1_full_openmount|review-r19|credited | 16 | 10 | 10 | 0.3000 | 0.4000 | grader_credit: describes 3, does-not-describe 6, partially 1 |
| a1_full_openmount|review-r19|far-miss | 14 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full_openmount|review-r19|near-miss | 11 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_full_openmount|review-r19|stray | 116 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 6, wrong 3 |
| a1_full_openmount|review-r20|credited | 5 | 5 | 5 | 0.2000 | 0.4000 | grader_credit: describes 1, does-not-describe 3, partially 1 |
| a1_full_openmount|review-r20|far-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a1_full_openmount|review-r20|near-miss | 2 | 2 | 2 | 0.5000 | 1.0000 | grader_no_credit: does-not-describe 1, partially 1 |
| a1_full_openmount|review-r20|stray | 55 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 4, style 2, wrong 1 |
| a1_full_openmount|review-r21|credited | 54 | 10 | 10 | 0.0000 | 0.1000 | grader_credit: does-not-describe 9, partially 1 |
| a1_full_openmount|review-r21|far-miss | 7 | 7 | 7 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 7 |
| a1_full_openmount|review-r21|near-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a1_full_openmount|review-r21|stray | 179 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 3, style 1 |
| a1_full_openmount|review-r23|credited | 126 | 10 | 10 | 0.1000 | 0.1000 | grader_credit: describes 1, does-not-describe 9 |
| a1_full_openmount|review-r23|far-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a1_full_openmount|review-r23|near-miss | 35 | 10 | 10 | 0.7000 | 1.0000 | grader_no_credit: does-not-describe 7, partially 3 |
| a1_full_openmount|review-r23|stray | 135 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 2, wrong 2 |
| a1_full_openmount|review-r25|credited | 66 | 10 | 10 | 0.4000 | 0.5000 | grader_credit: describes 4, does-not-describe 5, partially 1 |
| a1_full_openmount|review-r25|near-miss | 15 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full_openmount|review-r25|stray | 98 | 10 | 10 | — | — | grader_no_credit: not-a-finding 8, wrong 2 |
| a1_full_openmount|review-r26|credited | 65 | 10 | 10 | 0.4000 | 0.5000 | grader_credit: describes 4, does-not-describe 5, partially 1 |
| a1_full_openmount|review-r26|far-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_full_openmount|review-r26|near-miss | 15 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_full_openmount|review-r26|stray | 63 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, real 2, wrong 1 |
| a1_full_openmount|review-r27|credited | 36 | 10 | 10 | 0.5000 | 0.5000 | grader_credit: describes 5, does-not-describe 5 |
| a1_full_openmount|review-r27|far-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a1_full_openmount|review-r27|near-miss | 5 | 5 | 5 | 0.4000 | 1.0000 | grader_no_credit: does-not-describe 2, partially 3 |
| a1_full_openmount|review-r27|stray | 94 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 3, style 2, wrong 4 |
| a1_full_openmount|review-r28|credited | 16 | 10 | 10 | 0.2000 | 0.6000 | grader_credit: describes 2, does-not-describe 4, partially 4 |
| a1_full_openmount|review-r28|near-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_full_openmount|review-r28|stray | 148 | 10 | 10 | — | — | grader_no_credit: not-a-finding 5, real 3, wrong 2 |
| a1_full|review-r11|credited | 21 | 10 | 10 | 0.4000 | 0.8000 | grader_credit: describes 4, does-not-describe 2, partially 4 |
| a1_full|review-r11|near-miss | 20 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full|review-r11|stray | 73 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 4, wrong 3 |
| a1_full|review-r15|credited | 71 | 10 | 10 | 0.1000 | 0.2000 | grader_credit: describes 1, does-not-describe 8, partially 1 |
| a1_full|review-r15|far-miss | 12 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_full|review-r15|near-miss | 12 | 10 | 10 | 0.8000 | 1.0000 | grader_no_credit: does-not-describe 8, partially 2 |
| a1_full|review-r15|stray | 43 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 6, wrong 1 |
| a1_full|review-r16|credited | 8 | 8 | 8 | 0.1250 | 0.2500 | grader_credit: describes 1, does-not-describe 6, partially 1 |
| a1_full|review-r16|far-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_full|review-r16|near-miss | 15 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_full|review-r16|stray | 129 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, real 2, wrong 1 |
| a1_full|review-r19|credited | 11 | 10 | 10 | 0.2000 | 0.4000 | grader_credit: describes 2, does-not-describe 6, partially 2 |
| a1_full|review-r19|far-miss | 14 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full|review-r19|near-miss | 21 | 10 | 10 | 0.9000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 9 |
| a1_full|review-r19|stray | 122 | 10 | 10 | — | — | grader_no_credit: not-a-finding 4, real 2, style 2, wrong 2 |
| a1_full|review-r22|credited | 20 | 10 | 10 | 0.0000 | 0.1000 | grader_credit: does-not-describe 9, partially 1 |
| a1_full|review-r22|far-miss | 9 | 9 | 9 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 9 |
| a1_full|review-r22|near-miss | 12 | 10 | 10 | 0.9000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 9 |
| a1_full|review-r22|stray | 120 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, real 2, wrong 1 |
| a1_full|review-r23|credited | 121 | 10 | 10 | 0.1000 | 0.3000 | grader_credit: describes 1, does-not-describe 7, partially 2 |
| a1_full|review-r23|far-miss | 6 | 6 | 6 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 6 |
| a1_full|review-r23|near-miss | 35 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_full|review-r23|stray | 139 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 2, style 1, wrong 1 |
| a1_full|review-r24|credited | 115 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a1_full|review-r24|near-miss | 17 | 10 | 10 | 0.9000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 9 |
| a1_full|review-r24|stray | 74 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 1, style 2, wrong 1 |
| a1_full|review-r25|credited | 68 | 10 | 10 | 0.3000 | 0.7000 | grader_credit: describes 3, does-not-describe 3, partially 4 |
| a1_full|review-r25|near-miss | 12 | 10 | 10 | 0.7000 | 0.7000 | grader_no_credit: describes 3, does-not-describe 7 |
| a1_full|review-r25|stray | 65 | 10 | 10 | — | — | grader_no_credit: not-a-finding 8, real 2 |
| a1_full|review-r26|credited | 55 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a1_full|review-r26|near-miss | 24 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_full|review-r26|stray | 46 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 2, wrong 2 |
| a1_full|review-r27|credited | 20 | 10 | 10 | 0.4000 | 0.4000 | grader_credit: describes 4, does-not-describe 6 |
| a1_full|review-r27|far-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a1_full|review-r27|near-miss | 5 | 5 | 5 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 5 |
| a1_full|review-r27|stray | 90 | 10 | 10 | — | — | grader_no_credit: not-a-finding 5, real 2, style 1, wrong 2 |
| a1_full|review-r28|credited | 19 | 10 | 10 | 0.3000 | 0.6000 | grader_credit: describes 3, does-not-describe 4, partially 3 |
| a1_full|review-r28|near-miss | 4 | 4 | 4 | 0.7500 | 1.0000 | grader_no_credit: does-not-describe 3, partially 1 |
| a1_full|review-r28|stray | 159 | 10 | 10 | — | — | grader_no_credit: not-a-finding 8, real 2 |
| a1_review_only|review-r11|credited | 23 | 10 | 10 | 0.4000 | 0.6000 | grader_credit: describes 4, does-not-describe 4, partially 2 |
| a1_review_only|review-r11|far-miss | 3 | 3 | 3 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 3 |
| a1_review_only|review-r11|near-miss | 4 | 4 | 4 | 0.5000 | 0.5000 | grader_no_credit: describes 2, does-not-describe 2 |
| a1_review_only|review-r11|stray | 62 | 10 | 10 | — | — | grader_no_credit: not-a-finding 2, real 6, wrong 2 |
| a1_review_only|review-r14|credited | 16 | 10 | 10 | 0.1000 | 0.5000 | grader_credit: describes 1, does-not-describe 5, partially 4 |
| a1_review_only|review-r14|far-miss | 15 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_review_only|review-r14|near-miss | 9 | 9 | 9 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 9 |
| a1_review_only|review-r14|stray | 55 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, style 1, wrong 2 |
| a1_review_only|review-r16|credited | 3 | 3 | 3 | 0.0000 | 0.0000 | grader_credit: does-not-describe 3 |
| a1_review_only|review-r16|far-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a1_review_only|review-r16|near-miss | 3 | 3 | 3 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 3 |
| a1_review_only|review-r16|stray | 46 | 10 | 10 | — | — | grader_no_credit: not-a-finding 2, real 5, wrong 3 |
| a1_review_only|review-r19|credited | 2 | 2 | 2 | 0.5000 | 0.5000 | grader_credit: describes 1, does-not-describe 1 |
| a1_review_only|review-r19|far-miss | 11 | 10 | 10 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 10 |
| a1_review_only|review-r19|near-miss | 3 | 3 | 3 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 3 |
| a1_review_only|review-r19|stray | 25 | 10 | 10 | — | — | grader_no_credit: not-a-finding 1, real 5, style 3, wrong 1 |
| a1_review_only|review-r21|credited | 11 | 10 | 10 | 0.0000 | 0.2000 | grader_credit: does-not-describe 8, partially 2 |
| a1_review_only|review-r21|far-miss | 10 | 10 | 10 | 0.9000 | 1.0000 | grader_no_credit: does-not-describe 9, partially 1 |
| a1_review_only|review-r21|near-miss | 2 | 2 | 2 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 2 |
| a1_review_only|review-r21|stray | 77 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 4, wrong 3 |
| a1_review_only|review-r22|credited | 12 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a1_review_only|review-r22|far-miss | 23 | 10 | 10 | 0.9000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 9 |
| a1_review_only|review-r22|near-miss | 9 | 9 | 9 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 9 |
| a1_review_only|review-r22|stray | 80 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 3, style 1, wrong 3 |
| a1_review_only|review-r23|credited | 50 | 10 | 10 | 0.2000 | 0.3000 | grader_credit: describes 2, does-not-describe 7, partially 1 |
| a1_review_only|review-r23|far-miss | 7 | 7 | 7 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 7 |
| a1_review_only|review-r23|near-miss | 12 | 10 | 10 | 0.5000 | 1.0000 | grader_no_credit: does-not-describe 5, partially 5 |
| a1_review_only|review-r23|stray | 49 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 3, style 2, wrong 2 |
| a1_review_only|review-r24|credited | 71 | 10 | 10 | 0.2000 | 0.4000 | grader_credit: describes 2, does-not-describe 6, partially 2 |
| a1_review_only|review-r24|far-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_review_only|review-r24|near-miss | 15 | 10 | 10 | 0.8000 | 0.9000 | grader_no_credit: describes 1, does-not-describe 8, partially 1 |
| a1_review_only|review-r24|stray | 46 | 10 | 10 | — | — | grader_no_credit: not-a-finding 3, real 2, wrong 5 |
| a1_review_only|review-r25|credited | 34 | 10 | 10 | 0.5000 | 0.7000 | grader_credit: describes 5, does-not-describe 3, partially 2 |
| a1_review_only|review-r25|stray | 47 | 10 | 10 | — | — | grader_no_credit: not-a-finding 6, real 3, style 1 |
| a1_review_only|review-r26|credited | 43 | 10 | 10 | 0.5000 | 0.6000 | grader_credit: describes 5, does-not-describe 4, partially 1 |
| a1_review_only|review-r26|far-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a1_review_only|review-r26|near-miss | 4 | 4 | 4 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 4 |
| a1_review_only|review-r26|stray | 35 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, real 1, wrong 2 |
| a1_review_only|review-r27|credited | 20 | 10 | 10 | 0.6000 | 0.7000 | grader_credit: describes 6, does-not-describe 3, partially 1 |
| a1_review_only|review-r27|far-miss | 3 | 3 | 3 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 3 |
| a1_review_only|review-r27|near-miss | 7 | 7 | 7 | 0.8571 | 1.0000 | grader_no_credit: does-not-describe 6, partially 1 |
| a1_review_only|review-r27|stray | 52 | 10 | 10 | — | — | grader_no_credit: not-a-finding 7, real 2, style 1 |
| a1_review_only|review-r28|credited | 13 | 10 | 10 | 0.2000 | 0.5000 | grader_credit: describes 2, does-not-describe 5, partially 3 |
| a1_review_only|review-r28|near-miss | 1 | 1 | 1 | 1.0000 | 1.0000 | grader_no_credit: does-not-describe 1 |
| a1_review_only|review-r28|stray | 81 | 10 | 10 | — | — | grader_no_credit: not-a-finding 4, real 4, style 1, wrong 1 |

## Judge-corrected recall and precision per arm (strict, Horvitz–Thompson)

| arm | cells | PRs | recall (grader) | recall corrected | 95 % | precision (grader) | precision corrected | 95 % |
|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 14 | 0.2757 | 0.0656 | [0.0319, 0.1013] | 0.2367 | 0.3321 | [0.2725, 0.4040] |
| a0_bare_matched | 25 | 13 | 0.4906 | 0.0378 | [-0.0292, 0.1488] | 0.2124 | 0.3547 | [0.2716, 0.4605] |
| a1_full | 17 | 11 | 0.6308 | 0.0156 | [-0.0698, 0.1200] | 0.2593 | 0.1995 | [0.1684, 0.2419] |
| a1_full_openmount | 23 | 12 | 0.6126 | 0.0619 | [0.0018, 0.1410] | 0.2692 | 0.2485 | [0.1802, 0.3339] |
| a1_review_only | 20 | 12 | 0.4714 | 0.1257 | [0.0459, 0.2322] | 0.2544 | 0.2935 | [0.2178, 0.3804] |

## Judge-corrected recall and precision per arm (lenient, Horvitz–Thompson)

| arm | cells | PRs | recall (grader) | recall corrected | 95 % | precision (grader) | precision corrected | 95 % |
|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 14 | 0.2757 | 0.1173 | [0.0640, 0.1830] | 0.2367 | 0.3941 | [0.3318, 0.4668] |
| a0_bare_matched | 25 | 13 | 0.4906 | 0.0897 | [0.0135, 0.2136] | 0.2124 | 0.3925 | [0.3007, 0.5012] |
| a1_full | 17 | 11 | 0.6308 | 0.0958 | [-0.0011, 0.2450] | 0.2593 | 0.2481 | [0.2076, 0.3043] |
| a1_full_openmount | 23 | 12 | 0.6126 | 0.1648 | [0.0922, 0.2269] | 0.2692 | 0.3106 | [0.2307, 0.4007] |
| a1_review_only | 20 | 12 | 0.4714 | 0.2062 | [0.1228, 0.3241] | 0.2544 | 0.3447 | [0.2766, 0.4249] |

Strays rated real: 196.
