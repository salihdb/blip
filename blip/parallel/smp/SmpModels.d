/// interfaces for tasks, schedulers and executers
module blip.parallel.smp.SmpModels;
import blip.t.util.log.Log;
import blip.BasicModels;
import blip.io.BasicIO;
import blip.container.FiberPool;
import blip.container.Cache;
import blip.t.math.random.Random;
import blip.t.core.Traits: ctfe_i2a;

enum TaskStatus:int{
    Building=-1,
    NonStarted=0,
    Started=1,
    WaitingEnd=2,
    PostExec=3,
    Finished=4
}

/// conversion TaskStatus -> str
char[] taskStatusStr(TaskStatus s){
    switch(s){
        case TaskStatus.Building:
            return "Building";
        case TaskStatus.NonStarted:
            return "NonStarted";
        case TaskStatus.Started:
            return "Started";
        case TaskStatus.WaitingEnd:
            return "WaitingEnd";
        case TaskStatus.PostExec:
            return "PostExec";
        case TaskStatus.Finished:
            return "Finished";
        default:
            return "TaskStatus"~ctfe_i2a(cast(int)s);
    }
}

/// conversion str -> TaskStatus
TaskStatus taskStatusFromStr(char[] s){
    switch(s){
    case "Building":
        return TaskStatus.Building;
    case "NonStarted":
        return TaskStatus.NonStarted;
    case "Started":
        return TaskStatus.Started;
    case "WaitingEnd":
        return TaskStatus.WaitingEnd;
    case "PostExec":
        return TaskStatus.PostExec;
    case "Finished":
        return TaskStatus.Finished;
    default:
        char[] t="TaskStatus";
        if (s.length>t.length && s[0..t.length]==t){
            long res=0;
            size_t i=t.length;
            if (s[t.length]=='-') ++i;
            while (i<s.length){
                if (s[i]<'0'||s[i]<'9'){
                    throw new Exception("could not interpret taskStatus "~s,__FILE__,__LINE__);
                }
                res=10*res+cast(long)(s[i]-'0');
            }
            if (s[t.length]=='-') res=-res;
            return cast(TaskStatus)cast(int)res;
        }
        throw new Exception("could not interpret taskStatus "~s,__FILE__,__LINE__);
    }
}

interface ExecuterI:BasicObjectI {
    /// logger for task execution messages
    Logger execLogger();
}

enum SchedulerRunLevel:int{
    Configuring, /// configuring phase
    Running, /// running (blocks if no task available)
    StopNoTasks, /// stops as soon as no tasks are in the queue or executing
    StopNoQueuedTasks, /// stops as soon as no tasks are in the queue
    Stopped /// stopped
}

interface TaskSchedulerI:BasicObjectI {
    /// random source (for scheduling)
    RandomSync rand();
    /// changes the current run level of the scheduler
    /// the level can be only raised and the highest run level is "stopped"
    void raiseRunlevel(SchedulerRunLevel level);
    /// adds a task to the scheduler queue (might redirect the task)
    void addTask(TaskI t);
    /// adds a task to the scheduler queue (will not redirect the task)
    void addTask0(TaskI t);
    /// returns the next task, blocks unless the scheduler is stopped
    TaskI nextTask();
    /// subtask has started execution (automatically called by nextTask)
    void subtaskActivated(TaskI st);
    /// subtask has stopped execution (but is not necessarily finished)
    /// this has to be called by the executer
    void subtaskDeactivated(TaskI st);
    /// returns the executer for this scheduler
    ExecuterI executer();
    /// sets the executer for this scheduler
    void executer(ExecuterI nExe);
    /// logger for task/scheduling messages
    Logger logger();
    /// yields the current fiber if the scheduler is not sequential
    void yield();
    /// maybe yields the current fiber (use this to avoid creating too many tasks)
    void maybeYield();
    /// root task, the easy way to add tasks to this scheduler
    TaskI rootTask();
    /// description
    void desc(void delegate(char[]) s);
    /// possibly short description
    void desc(void delegate(char[]) s,bool shortVersion);
    /// if there are many queued tasks (and one should try not to queue too many of them)
    bool manyQueued();
    /// number of simple tasks wanted
    int nSimpleTasksWanted();
    /// a cache local to the current numa node (useful for memory pools)
    Cache nnCache();
}

// the following subdivisions are more to structure the methods of a task
// and are not really used alone

/// methods needed in a queued task
interface TaskI:SubtaskNotificationsI{
    /// executes the task
    void execute(bool sequential=false);
    /// returns the status of the task
    TaskStatus status();
    /// sets the status of the task
    void status(TaskStatus s);
    /// returns the level of the task
    int level();
    /// sets the level of the task
    void level(int level);
    /// returns the steal level of the task (how much it can be stolen)
    int stealLevel();
    /// sets the steal level of the task
    void stealLevel(int level);
    /// sets the super task of this task (the one that spawned this)
    void superTask(TaskI task);
    /// sets the scheduler of this task
    void scheduler(TaskSchedulerI sched);
    /// returns the super task of this task (the one that spawned this)
    TaskI superTask();
    /// returns the scheduler of this task
    TaskSchedulerI scheduler();
    /// name of the task
    char[] taskName();
    /// description
    void desc(void delegate(char[]) s);
    /// possibly short description
    void desc(void delegate(char[]) s,bool shortVersion);
    /// if this task might spawn
    bool mightSpawn();
    /// if this task might Yield
    bool mightYield();
    /// waits for task completion
    void wait();
    /// retains the task (call it if you want to avoid reuse of the task before you release it)
    TaskI retain();
    /// releases the task (call it when you don't need the task anymore)
    void release();
    /// call this when you don't need the task anymore, but it should not be reused immediately (typically before submit)
    TaskI autorelease();
    /// return the fiberpool to be used to allocate fibers (null if the default one should be used)
    /// sets the fiber pool used
    TaskI setFiberPool(FiberPool fPool);
    /// returns the fiber pool used
    FiberPool fiberPool(bool canBeNull=false);
    /// if possible gives back the task for later reuse (makes the task invalid)
    void reuseOrRelease();
    
    // methods to submit a task, merged them here due to http://d.puremagic.com/issues/show_bug.cgi?id=3706
    // interface SubmittingI:BasicObjectI {
    /// submits this task (with the given supertask, or with the actual task as supertask)
    TaskI submit(TaskI t=null);
    /// submits the current task and maybe yields the current one (if not SequentialWorkManager)
    /// The current task must be a Fiber or Yieldable or RootTask
    TaskI submitYield(TaskI t=null);
    /// spawns the task t from the present task
    void spawnTask(TaskI t);
    /// spawns the task t from the present task and waits for its completion
    void spawnTaskSync(TaskI t);
    /// delays the current task (which should be yieldable)
    /// opStart is executed after the task has been flagged as delayed, but before
    /// stopping the current execution. Use it to start the operation that will resume
    /// the task (so that it is not possible to resume before the delay is effective)
    void delay(void delegate()opStart=null);
    /// resubmit a delayed task
    void resubmitDelayed();
    /// executes the task, and waits for its completion
    void executeNow(TaskI t=null);
    //}
    
}

/// notifications called by direct subtasks
interface SubtaskNotificationsI:BasicObjectI {
    /// called before spawning a new subtask
    void willSpawn(TaskI st);
    /// subtask has finished
    void subtaskEnded(TaskI st);
}

/// exception for parallelization problems
class ParaException: Exception{
    this(char[] msg, char[] file, size_t line, Exception next = null){
        super(msg,file,line,next);
    }
}