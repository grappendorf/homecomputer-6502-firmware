100 PRINT "Guess my number (1..100)!"
110 LET N=INT(RND(1)*100)+1
120 LET I=0
130 PRINT "Your guess: ";
140 INPUT X
150 LET I=I+1
160 IF N=X THEN GOTO 220
170 IF N>X THEN GOTO 200
180 PRINT "No, my number is smaller."
190 GOTO 130
200 PRINT "No, my number is bigger."
210 GOTO 130
220 PRINT "Congratulations, ";N;" was my number!"
230 PRINT "You needed ";I;" guesses."
