# Throwaway (ci/ipa only): the candidate fix for the lost PASS lines, applied to the two touch
# fixtures before they are built. stdout goes out a line at a time, and every exit() waits a
# moment after flushing so `simctl launch --console` can relay the last lines.
import re, sys
FLUSH = '''
#include <unistd.h>
static void AKFixtureFlushBeforeExit(void) { fflush(stdout); fflush(stderr); usleep(300000); }
'''
SETUP = 'setvbuf(stdout, NULL, _IOLBF, 0); atexit(AKFixtureFlushBeforeExit); '
for path in sys.argv[1:]:
    s = open(path).read()
    if 'AKFixtureFlushBeforeExit' in s:
        continue
    m = re.search(r'int main\(int argc, char \*\*argv\) \{', s)
    assert m, path
    s = s[:m.start()] + FLUSH + s[m.start():m.end()] + ' ' + SETUP + s[m.end():]
    open(path, 'w').write(s)
    print('patched', path)
