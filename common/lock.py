import fcntl

class lock:
    def __init__(self, lockFile):
        self.lockFile = lockFile
        # This will create it if it does not exist already
        self.handle = open(self.lockFile, 'w')
        # Bitwise OR fcntl.LOCK_NB if you need a non-blocking lock 
        fcntl.flock(self.handle, fcntl.LOCK_EX)
    
    def __del__(self):
        fcntl.flock(self.handle, fcntl.LOCK_UN)
        self.handle.close()
