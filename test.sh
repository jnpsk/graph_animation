#!/bin/bash

# #ukazka
perl draw.pl -t '[%Y/%m/%d %H:%M:%S]' -c y=0 -c "y=-0.1:x=[2009/05/11 20:11:00]" tests/data/sin-day-real.data  -e "split=2" -n "output/out" -f tests/conf/test.conf -xmin -Xmax -ymin -Ymax -e"ending=5:reverse=0"

# #minmax
# perl draw.pl -t '[%Y/%m/%d %H:%M:%S]' tests/data/sin-day-real.data  -e "split=10" -n "output/ymax0" -x'[2009/05/11 20:11:00]' -Y0 -e"ending=5:reverse=1"
# perl draw.pl -t '[%Y/%m/%d %H:%M:%S]' tests/data/sin-day-real.data  -e "split=10" -n "output/xLimits" -x'[2009/05/11 13:11:00]' -X'[2009/05/11 20:11:00]' -e"ending=5:reverse=1"

# # download, grid, legend
# perl draw.pl -t '[%H:%M:%S %d.%m.%Y]' https://users.fit.cvut.cz/~barinkl/data1 -n "output/dwnld" -l"Downloaded data1, grid, split3" -g"grid" -d -e "split=3"

# # files merge
# perl draw.pl -t '[%Y/%m/%d %H:%M:%S]' tests/data/test1.data tests/data/test3.data tests/data/test2.data -n "output/merge" -e "split=1"

# # ukazka speed time fps
# perl draw.pl -t '%H:%M:%S' https://users.fit.cvut.cz/~barinkl/data2 -n "output/fps" -e "split=3:color=blue" -e "reverse=1" -F 5
# perl draw.pl -t '%H:%M:%S' https://users.fit.cvut.cz/~barinkl/data2 -n "output/fpsTime" -e "split=3:color=blue" -e "reverse=1" -F 5 -T 50
# perl draw.pl -t '%H:%M:%S' https://users.fit.cvut.cz/~barinkl/data2 -n "output/speedTime" -e "split=3:color=blue" -e "reverse=1" -S 5 -T 50

# # ukazka spatnheo conf file
# perl draw.pl https://users.fit.cvut.cz/~barinkl/data2 -f tests/conf/fault.conf

# # argumenty
# perl draw.pl -Q
# perl draw.pl -f /cantopen.txt
# perl draw.pl -T "ahoj"