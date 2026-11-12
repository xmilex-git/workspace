---- MODULE KeyRewindTraceData ----
EXTENDS Sequences
\* N1: traces/convert.py raw/n1.log.xz N1 auto 6500,7000  (btid 832, keys 6500 -> 1..1)
N1Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0],
  [a |-> "Rewind", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 1, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 2, flag |-> 0, key |-> 0]
>>
N1NK == 1
N1NOut == 2
N1Rlo == <<1, 1>>
N1Rhi == <<1, 1>>
N1M == <<{1}, {2}>>
N1Leaf == <<85>>
N1NPg == <<12>>
N1Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>>>
\* N2: traces/convert.py raw/n2.log.xz N2 auto 6500,7000  (btid 832, keys 6500,7000 -> 1..2)
N2Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 13, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 14, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 15, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 16, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 17, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 18, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 19, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 20, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 21, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 22, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 23, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 24, buf |-> 8136, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 6413, flag |-> 0, key |-> 0],
  [a |-> "Rewind", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 1, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 1, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "EndScan", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0]
>>
N2NK == 2
N2NOut == 2
N2Rlo == <<1, 2>>
N2Rhi == <<1, 2>>
N2M == <<{13956}, {16358}>>
N2Leaf == <<85, 1>>
N2NPg == <<24, 0>>
N2Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>, <<>>>>
\* N3: traces/convert.py raw/n3.log.xz N3 auto 6500,7000  (btid 832, keys 6500 -> 1..1)
N3Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 13, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 14, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 15, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 16, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 17, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 18, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 19, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 20, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 21, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 22, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 23, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 24, buf |-> 8136, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 6413, flag |-> 0, key |-> 0],
  [a |-> "Rewind", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 1, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 36, flag |-> 0, key |-> 0]
>>
N3NK == 1
N3NOut == 2
N3Rlo == <<1, 1>>
N3Rhi == <<1, 1>>
N3M == <<{13956}, {36}>>
N3Leaf == <<85>>
N3NPg == <<24>>
N3Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>>>
\* N4: traces/convert.py raw/n4.log.xz N4 auto 1,2  (btid 832, keys 2,1 -> 1..2)
N4Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0],
  [a |-> "Flip", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 1, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 1, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7544, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0]
>>
N4NK == 2
N4NOut == 2
N4Rlo == <<2, 1>>
N4Rhi == <<2, 2>>
N4M == <<{2}, {1}>>
N4Leaf == <<1, 85>>
N4NPg == <<0, 12>>
N4Pg == <<<<>>, <<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>>>
\* N5: traces/convert.py raw/n5.log.xz N5 auto 1,2  (btid 832, keys 1,2 -> 1..2)
N5Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 13, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 14, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 15, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 16, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 17, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 18, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 19, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 20, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 21, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 677, pg |-> 22, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "SoftStop", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 7457, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 203, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "EndScan", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0]
>>
N5NK == 2
N5NOut == 1
N5Rlo == <<1>>
N5Rhi == <<2>>
N5M == <<{}>>
N5Leaf == <<85, 85>>
N5NPg == <<22, 5>>
N5Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 677>>, <<678, 678, 678, 678, 203>>>>
\* R1: traces/convert.py raw/n1.log.xz R1 auto 6500,7000 stale-off (btid 832, keys 6500 -> 1..1)
R1Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0],
  [a |-> "Rewind", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 2, flag |-> 0, key |-> 0]
>>
R1NK == 1
R1NOut == 2
R1Rlo == <<1, 1>>
R1Rhi == <<1, 1>>
R1M == <<{1}, {2}>>
R1Leaf == <<85>>
R1NPg == <<12>>
R1Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>>>
\* R2: traces/convert.py raw/n2.log.xz R2 auto 6500,7000 skip-leaf (btid 832, keys 6500,7000 -> 1..2)
R2Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 13, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 14, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 15, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 16, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 17, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 18, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 19, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 20, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 21, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 22, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 23, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 24, buf |-> 8136, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 6413, flag |-> 0, key |-> 0],
  [a |-> "Rewind", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "Start", stale |-> 1, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "EndScan", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "Row", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 1, flag |-> 0, key |-> 0]
>>
R2NK == 2
R2NOut == 2
R2Rlo == <<1, 2>>
R2Rhi == <<1, 2>>
R2M == <<{13956}, {16358}>>
R2Leaf == <<85, 1>>
R2NPg == <<24, 0>>
R2Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678>>, <<>>>>
\* R3: traces/convert.py raw/n5.log.xz R3 auto 1,2 count-off (btid 832, keys 1,2 -> 1..2)
R3Log == <<
  [a |-> "Start", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 679, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 6, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 7, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 8, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 9, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 10, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 11, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Interrupt", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 7543, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 1, key |-> 0],
  [a |-> "KeyResume", stale |-> 0, n |-> 0, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 12, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 13, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 14, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 15, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 16, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 17, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 18, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 19, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 20, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 21, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "PageFill", stale |-> 0, n |-> 677, pg |-> 22, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 1],
  [a |-> "SoftStop", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 7457, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "Call", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0],
  [a |-> "LeafFill", stale |-> 0, n |-> 85, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 1, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 2, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 3, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 678, pg |-> 4, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "PageFill", stale |-> 0, n |-> 203, pg |-> 5, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "KeyDone", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 2],
  [a |-> "EndScan", stale |-> 0, n |-> 0, pg |-> 0, buf |-> 0, pos |-> 0, flag |-> 0, key |-> 0]
>>
R3NK == 2
R3NOut == 1
R3Rlo == <<1>>
R3Rhi == <<2>>
R3M == <<{}>>
R3Leaf == <<85, 85>>
R3NPg == <<22, 5>>
R3Pg == <<<<678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 678, 677>>, <<678, 678, 678, 678, 203>>>>
====
