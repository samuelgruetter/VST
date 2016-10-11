#!/bin/bash

cd .. # now we're in VST

coqc `cat .loadpath` -Q ./aes "" aes/aes.v aes/AES256.v aes/aesutils.v aes/aes_round_lemmas.v aes/forwarding_table_lemmas.v aes/verif_aes256.v

# takes forever:
# aes/mult_equiv_lemmas.v

cd ./aes # go back
