p='build/probe/as_is.swift'; t=open(p).read()
old='            for (index,t) in [1.0,3,7,15,23,31].enumerated() {'
new='            queue.asyncAfter(deadline:.now()+2.9) { print("AS-IS: packets sent", link.packets.count, "clock", clock) }\n'+old
assert old in t; open(p,'w').write(t.replace(old,new,1))
