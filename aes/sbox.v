Require Import List. Import ListNotations.
Require Import ZArith.
Local Open Scope Z_scope.

Definition sbox := [
  (* 0x00 through 0x0f: (hexadecimal) 63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab 76 *)
  99; 124; 119; 123; 242; 107; 111; 197; 48; 1; 103; 43; 254; 215; 171; 118;
  (* 0x10 through 0x1f: ca 82 c9 7d fa 59 47 f0 ad d4 a2 af 9c a4 72 c0 *)
  202; 130; 201; 125; 250; 89; 71; 240; 173; 212; 162; 175; 156; 164; 114; 192;
  (* 0x20 through 0x2f: b7 fd 93 26 36 3f f7 cc 34 a5 e5 f1 71 d8 31 15 *)
  183; 253; 147; 38; 54; 63; 247; 204; 52; 165; 229; 241; 113; 216; 49; 21;
  (* 0x30 through 0x3f: 04 c7 23 c3 18 96 05 9a 07 12 80 e2 eb 27 b2 75 *)
  4; 199; 35; 195; 24; 150; 5; 154; 7; 18; 128; 226; 235; 39; 178; 117;
  (* 0x40 through 0x4f: 09 83 2c 1a 1b 6e 5a a0 52 3b d6 b3 29 e3 2f 84 *)
  9; 131; 44; 26; 27; 110; 90; 160; 82; 59; 214; 179; 41; 227; 47; 132;
  (* 0x50 through 0x5f: 53 d1 00 ed 20 fc b1 5b 6a cb be 39 4a 4c 58 cf *)
  83; 209; 0; 237; 32; 252; 177; 91; 106; 203; 190; 57; 74; 76; 88; 207;
  (* 0x60 through 0x6f: d0 ef aa fb 43 4d 33 85 45 f9 02 7f 50 3c 9f a8 *)
  208; 239; 170; 251; 67; 77; 51; 133; 69; 249; 2; 127; 80; 60; 159; 168;
  (* 0x70 through 0x7f: 51 a3 40 8f 92 9d 38 f5 bc b6 da 21 10 ff f3 d2 *)
  81; 163; 64; 143; 146; 157; 56; 245; 188; 182; 218; 33; 16; 255; 243; 210;
  (* 0x80 through 0x8f: cd 0c 13 ec 5f 97 44 17 c4 a7 7e 3d 64 5d 19 73 *)
  205; 12; 19; 236; 95; 151; 68; 23; 196; 167; 126; 61; 100; 93; 25; 115;
  (* 0x90 through 0x9f: 60 81 4f dc 22 2a 90 88 46 ee b8 14 de 5e 0b db *)
  96; 129; 79; 220; 34; 42; 144; 136; 70; 238; 184; 20; 222; 94; 11; 219;
  (* 0xa0 through 0xaf: e0 32 3a 0a 49 06 24 5c c2 d3 ac 62 91 95 e4 79 *)
  224; 50; 58; 10; 73; 6; 36; 92; 194; 211; 172; 98; 145; 149; 228; 121;
  (* 0xb0 through 0xbf: e7 c8 37 6d 8d d5 4e a9 6c 56 f4 ea 65 7a ae 08 *)
  231; 200; 55; 109; 141; 213; 78; 169; 108; 86; 244; 234; 101; 122; 174; 8;
  (* 0xc0 through 0xcf: ba 78 25 2e 1c a6 b4 c6 e8 dd 74 1f 4b bd 8b 8a *)
  186; 120; 37; 46; 28; 166; 180; 198; 232; 221; 116; 31; 75; 189; 139; 138;
  (* 0xd0 through 0xdf: 70 3e b5 66 48 03 f6 0e 61 35 57 b9 86 c1 1d 9e *)
  112; 62; 181; 102; 72; 3; 246; 14; 97; 53; 87; 185; 134; 193; 29; 158;
  (* 0xe0 through 0xef: e1 f8 98 11 69 d9 8e 94 9b 1e 87 e9 ce 55 28 df *)
  225; 248; 152; 17; 105; 217; 142; 148; 155; 30; 135; 233; 206; 85; 40; 223;
  (* 0xf0 through 0xff: 8c a1 89 0d bf e6 42 68 41 99 2d 0f b0 54 bb 16 *)
  140; 161; 137; 13; 191; 230; 66; 104; 65; 153; 45; 15; 176; 84; 187; 22
].
Definition inv_sbox := [
  (* 0x00 through 0x0f (in hexadecimal) : 52 09 6a d5 30 36 a5 38 bf 40 a3 9e 81 f3 d7 fb *)
  82; 9; 106; 213; 48; 54; 165; 56; 191; 64; 163; 158; 129; 243; 215; 251;
  (* 0x10 through 0x1f: 7c e3 39 82 9b 2f ff 87 34 8e 43 44 c4 de e9 cb *)
  124; 227; 57; 130; 155; 47; 255; 135; 52; 142; 67; 68; 196; 222; 233; 203;
  (* 0x20 through 0x2f: 54 7b 94 32 a6 c2 23 3d ee 4c 95 0b 42 fa c3 4e *)
  84; 123; 148; 50; 166; 194; 35; 61; 238; 76; 149; 11; 66; 250; 195; 78;
  (* 0x30 through 0x3f: 08 2e a1 66 28 d9 24 b2 76 5b a2 49 6d 8b d1 25 *)  
  8; 46; 161; 102; 40; 217; 36; 178; 118; 91; 162; 73; 109; 139; 209; 37;
  (* 0x40 through 0x4f: 72 f8 f6 64 86 68 98 16 d4 a4 5c cc 5d 65 b6 92 *)
  114; 248; 246; 100; 134; 104; 152; 22; 212; 164; 92; 204; 93; 101; 182; 146;
  (* 0x50 through 0x5f: 6c 70 48 50 fd ed b9 da 5e 15 46 57 a7 8d 9d 84 *)
  108; 112; 72; 80; 253; 237; 185; 218; 94; 21; 70; 87; 167; 141; 157; 132;
  (* 0x60 through 0x6f: 90 d8 ab 00 8c bc d3 0a f7 e4 58 05 b8 b3 45 06 *)
  144; 216; 171; 0; 140; 188; 211; 10; 247; 228; 88; 5; 184; 179; 69; 6;
  (* 0x70 through 0x7f: d0 2c 1e 8f ca 3f 0f 02 c1 af bd 03 01 13 8a 6b *)
  208; 44; 30; 143; 202; 63; 15; 2; 193; 175; 189; 3; 1; 19; 138; 107;
  (* 0x80 through 0x8f: 3a 91 11 41 4f 67 dc ea 97 f2 cf ce f0 b4 e6 73 *)
  58; 145; 17; 65; 79; 103; 220; 234; 151; 242; 207; 206; 240; 180; 230; 115;
  (* 0x90 through 0x9f: 96 ac 74 22 e7 ad 35 85 e2 f9 37 e8 1c 75 df 6e *)
  150; 172; 116; 34; 231; 173; 53; 133; 226; 249; 55; 232; 28; 117; 223; 110;
  (* 0xa0 through 0xaf: 47 f1 1a 71 1d 29 c5 89 6f b7 62 0e aa 18 be 1b *)
  71; 241; 26; 113; 29; 41; 197; 137; 111; 183; 98; 14; 170; 24; 190; 27;
  (* 0xb0 through 0xbf: fc 56 3e 4b c6 d2 79 20 9a db c0 fe 78 cd 5a f4 *)
  252; 86; 62; 75; 198; 210; 121; 32; 154; 219; 192; 254; 120; 205; 90; 244;
  (* 0xc0 through 0xcf: 1f dd a8 33 88 07 c7 31 b1 12 10 59 27 80 ec 5f *)
  31; 221; 168; 51; 136; 7; 199; 49; 177; 18; 16; 89; 39; 128; 236; 95;
  (* 0xd0 through 0xdf: 60 51 7f a9 19 b5 4a 0d 2d e5 7a 9f 93 c9 9c ef *)
  96; 81; 127; 169; 25; 181; 74; 13; 45; 229; 122; 159; 147; 201; 156; 239;
  (* 0xe0 through 0xef: a0 e0 3b 4d ae 2a f5 b0 c8 eb bb 3c 83 53 99 61 *)
  160; 224; 59; 77; 174; 42; 245; 176; 200; 235; 187; 60; 131; 83; 153; 97; 
  (* 0xf0 through 0xff: 17 2b 04 7e ba 77 d6 26 e1 69 14 63 55 21 0c 7d *)
  23; 43; 4; 126; 186; 119; 214; 38; 225; 105; 20; 99; 85; 33; 12; 125
].
