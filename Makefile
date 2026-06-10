# LPFG compiler has some logic to invoke the right Makefile.
# If a file named 'Makefile' exists in this folder, it uses
# Makefile.ATE to make. It fails if Makefile.ATE does not exist.
# If the 'Makefile' does not exist, it falls back to installation default Makefile.
# So, in a way, 'Makefile' itself is just a flag.
# Actual content of my makefile is at Makefile.ATE
