package simulator

import "core:os"

simulateSyscall0 :: proc(prg: ^Program, callNum: int) -> (int, ErrorMsg) {
    switch callNum {
        case 24: {
            // sys_sched_yield
        }
        case 34: {
            // sys_pause
        }
        case 39: {
            // sys_getpid
        }
        case 57: {
            // sys_fork
        }
        case 58: {
            // sys_vfork
        }
        case 162: {
            // sys_sync
        }
    }
    return 1, "Invalid or unsupported Syscall0"
}

simulateSyscall1 :: proc(prg: ^Program, callNum: int, arg1: Value) -> (ret:int = -1, err:ErrorMsg = nil) {
    switch callNum {
        case 3: {
            // sys_close(int fd)
            fd := getInnerInt(arg1) or_return
            return int(os.close(os.Handle(fd))), nil
        }
        case 32: {
            // sys_dup(int fd)
        }
        case 60: {
            // sys_exit(int exitcode)
            ExitCode = getInnerInt(arg1) or_return

            return ExitCode, "exit"
        }
        case 80: {
            // sys_chdir(char* filename)
        }
        case 81: {
            // sys_fchdir(int fd)
        }
        case 84: {
            // sys_rmdir(char* pathname)
        }

    }
    return 1, "Invalid or unsupported Syscall1"
}

simulateSyscall2 :: proc(prg: ^Program, callNum: int, arg1, arg2: Value) -> (ret:int = -1, err:ErrorMsg = nil) {
    switch callNum {
        case 79:{
            // getcwd(char* buf, ulong size)
        }
        case 82: {
            // rename(char* oldname, char* newname)
        }
    }
    return 1, "Invalid or unsupported Syscall2"
}

simulateSyscall3 :: proc(prg: ^Program, callNum: int, arg1, arg2, arg3: Value) -> (r:int = -1, err:ErrorMsg) {
    switch callNum {
        case 0: {
            // sys_read(int fd, char* buf, size_t len)
        }
        case 1: {
            // sys_write(int fd, char* buf, size_t len)
            fd := getInnerInt(arg1) or_return
            buf := (^string)(getInnerPtr(arg2) or_return)

            len := getInnerInt(arg3) or_return
            ret, err := os.write_string(os.Handle(fd), buf[:len])
            return ret, nil
        }
        case 2: {
            // fd:int sys_open(char* fileName, int flags, int mode)
        }
        case 41: {
            // sys_socket(int family, int type, int protocol)
        }
        case 42: {
            // sys_connect(int fd, struct sockaddr *uservaddr, int addrlen)
        }
        case 43: {
            // sys_accept(int fd, struct sockaddr *upeer_sockaddr, int *upeer_addrlen)
        }
        case 59: {
            // sys_execve(char* filename, char*[] argv, char*[] envp)
        }
    }
    return 1, "Invalid or unsupported Syscall3"
}
