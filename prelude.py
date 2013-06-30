# -*- coding: latin-1 -*-
from __future__ import print_function
import re, json
def typeof(t):
    if t is None: return 'undefined'
    elif isinstance(t, bool): return 'boolean'
    elif isinstance(t, str): return 'string'
    elif isinstance(t, int) or isinstance(t, float): return 'number'
    elif hasattr(t, '__call__'): return 'function'
    else: return 'object'

def list_indexOf(l, v):
    try:
        return l.index(v)
    except:
        return -1

parseFloat = float
parseInt = int

class jsdict(object):
    def __init__(self, d):
        self.__dict__.update(d)
    def __getitem__(self, name):
        if name in self.__dict__:
          return self.__dict__[name]
        else:
          return None
    def __setitem__(self, name, value):
        self.__dict__[name] = value
        return value
    def __getattr__(self, name):
        try:
            return getattr(self, name)
        except:
            return None
    def __setattr__(self, name, value):
        self[name] = value
        return value
    def __contains__(self, name):
        return name in self.__dict__
    def __repr__(self):
        return str(self.__dict__)

class RegExp(object):
    def __init__(self, pattern, flags=''):
        self.flags = flags
        pyflags = 0 | re.M if 'm' in flags else 0 | re.I if 'i' in flags else 0
        self.source = pattern
        self.pattern = re.compile(pattern, pyflags)
    def test(self, s):
        return self.pattern.search(s) is not None

console = jsdict({"log":print})
JSON = jsdict({"stringify": lambda a,b=None,c=None:json.dumps(a, default=b, indent=c)})
