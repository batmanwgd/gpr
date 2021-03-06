#!/usr/bin/env python

import subprocess, os, shutil, time

src_dir = "src"
if not os.path.exists(src_dir):
    os.mkdir(src_dir)

PN=10

for x in range(1, PN):
    f = open("%s/p%d.adb" % (src_dir, x), "w+")
    f.write("with P%d;\n" % (x + 1))
    f.write("procedure P%d is\n" % x)
    f.write("begin\n")
    f.write("   P%d;\n" % (x + 1))
    f.write("end P%d;\n" % x)
    f.close
    f = open("%s/p%d.ads" % (src_dir, x), "w+")
    f.write("procedure P%d;\n" % x)
    f.close

f = open("%s/p%d.ads" % (src_dir, PN), "w+")
f.write("procedure P%d;\n" % PN)
f.close
f = open("%s/p%d.adb" % (src_dir, PN), "w+")
f.write("procedure P%d is\n" % PN)
f.write("begin\n")
f.write("   null;\n")
f.write("end P%d;\n" % PN)
f.close

del f # Otherwise last file would not be written before compilation

subprocess.call(["gprbuild", "-p", "-q"])

EXEC="obj/check_mem"
first_high=False
first_final=False

#  Run driver 2 times
for r in range(0, 2):
    subprocess.call([EXEC, str(r * 2 + 1)])
    ofn = open("run%d.out" % r, "w+");
    subprocess.call(["gnatmem", "0", EXEC], stdout=ofn)
    ofn.seek(0)
    for line in ofn:
       if line[0:8] == "   Final":
           if first_final:
               if first_final == line:
                   print "OK final water mark"
               else:
                   print first_final + line
           else:
              first_final = line

       elif line[0:7] == "   High":
           if first_high:
               if first_high == line:
                   print "OK high water mark"
               else:
                   print first_high + line
               break
           else:
              first_high = line

    ofn.close()
