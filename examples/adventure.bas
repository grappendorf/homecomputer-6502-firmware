100 LET S=0
110 PRINT "You are in an empty room."
120 PRINT "There are doors in each wall."
130 PRINT "You can go n,s,w,e: ";
140 INPUT D$
150 IF D$="n" THEN GOTO 300
160 IF D$="s" THEN GOTO 300
170 IF D$="w" THEN GOTO 400
180 IF D$="e" THEN GOTO 500
190 PRINT "Sorry, i don't understand you."
200 GOTO 130
300 IF D$="n" THEN LET S=S+1
310 IF D$="s" THEN LET S=S-1
320 IF S=0 THEN GOTO 110
330 PRINT "You're walking through a long corridor."
340 PRINT "There are doors to the west and east."
350 GOTO 130
400 PRINT "You're in the lab of the mad scientist."
410 PRINT "You're dead!"
420 END
500 PRINT "Hell, yeah! You escaped!"
