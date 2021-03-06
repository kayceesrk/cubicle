const  ---- Configuration parameters ----

  PROC_NUM : 12;

type   ---- Type declarations ----

  -- PROC : scalarset(PROC_NUM);
  PROC : 1..PROC_NUM;
  LOCATION : enum {L0, L1, L2, L3, L4, L5, L6, L7};

var   ---- State variables ----

  A : array [PROC] of LOCATION;
  B : array [PROC] of boolean;
  S : array [PROC] of boolean;
  W : array [PROC] of boolean;

---- Initial states ----

startstate "Init"
  for x : PROC do
    A[x] := L0; S[x] := false; W[x] := false; B[x] := False;
  end;
end;

---- State transitions ----

ruleset x : PROC do rule "t0"
  A[x] = L0
==>
  A[x] := L1; B[x] := true;
end end;


ruleset x : PROC do rule "t1"
  A[x] = L1 & forall y : PROC do (x = y | S[y] = false) end
==>
  A[x] := L2; B[x] := false;
end end;


ruleset x : PROC do rule "t2"
  A[x] = L2
==>
  A[x] := L3; S[x] := true; W[x] := true;
end end;


ruleset x : PROC; y : PROC do rule "t3_then"
  x != y & A[x] = L3 & B[y] = false & W[y] = false
==>
  A[x] := L4; S[x] := false;
end end;


ruleset x : PROC do rule "t3_else"
  A[x] = L3 & forall y : PROC do (x = y | B[y] = true | W[y] = true) end
==>
  A[x] := L5; W[x] := false;
end end;


ruleset x : PROC; y : PROC do rule "t4"
  x != y & A[x] = L4 & S[y] = true & W[y] = false
==>
  A[x] := L5; S[x] := true; W[x] := false;
end end;


ruleset x : PROC do rule "t5"
  A[x] = L5 & forall y : PROC do (x = y | W[y] = false) end
==>
  A[x] := L6;
end end;


ruleset x : PROC do rule "t6"
  A[x] = L6 & forall j : PROC do (x <= j | S[j] = false) end
==>
  A[x] := L7;
end end;


ruleset x : PROC do rule "t7"
  A[x] = L7
==>
  A[x] := L0; S[x] := false;
end end;

---- Invariant properties ----

invariant "Mex"
  forall z1 : PROC do forall z2 : PROC do
    z1 != z2 -> (A[z1] = L7 -> A[z2] != L7)
  end end;
