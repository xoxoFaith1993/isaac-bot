// Decompile chosen functions of the analysed exe to C text files, for reading enemy AI.
// Arguments: <out_dir> <target> [<target> ...]
//   target = an address (0x4a1b20) or a name (Entity_NPC::Update)
//   prefix "npc:" (or "player:", "proj:", "ent:") first moves the function into that class as __thiscall, so its first
//   argument is typed Entity_NPC* and fields read as this->state, this->i1 ...
//   suffix "+NewName" renames it (e.g. npc:0x4a1b20+ai_haunt; "=" is split off by Windows batch files)
// Output: one .c file per target plus <out_dir>/callees.txt (what each target calls).
// Why (2026-11-26, RE pilot): the output stays local (gitignored); we commit only what we learn.
// @category IsaacBot
import ghidra.app.decompiler.*;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import java.nio.file.*;
import java.util.*;

public class DecompileFns extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Path out = Paths.get(args[0]);
        Files.createDirectories(out);
        StringBuilder callees = new StringBuilder();
        List<Function> todo = new ArrayList<>();
        for (int i = 1; i < args.length; i++) {
            String t = args[i];
            // class prefixes: npc: player: proj: ent: (types the first argument as that struct)
            String cls = null;
            String[][] pre = {{"npc:", "Entity_NPC"}, {"player:", "Entity_Player"}, {"proj:", "Entity_Projectile"}, {"ent:", "Entity"}};
            for (String[] pp : pre) if (t.startsWith(pp[0])) { cls = pp[1]; t = t.substring(pp[0].length()); }
            // "raw:" moves the function back to the global namespace (untyped this), for functions whose
            // decompile fails with a typed this ("PTRSUB off of non structured pointer type", 2026-11-26)
            boolean raw = t.startsWith("raw:");
            if (raw) t = t.substring(4);
            String rename = null;
            if (t.contains("+")) { rename = t.substring(t.indexOf('+') + 1); t = t.substring(0, t.indexOf('+')); }
            Function fn = findTarget(t);
            if (fn == null) { println("not found: " + t); continue; }
            if (cls != null) {
                SymbolTable st = currentProgram.getSymbolTable();
                Namespace ns = st.getNamespace(cls, currentProgram.getGlobalNamespace());
                if (ns == null) ns = st.createClass(currentProgram.getGlobalNamespace(), cls, SourceType.USER_DEFINED);
                fn.setParentNamespace(ns);
                fn.setCallingConvention("__thiscall");
            }
            if (raw) fn.setParentNamespace(currentProgram.getGlobalNamespace());
            if (rename != null) fn.setName(rename, SourceType.USER_DEFINED);
            todo.add(fn);
        }
        // PC safety caps (2026-11-26): the native decompile.exe once grew to 13.3 GB on a huge function and pushed
        // RAM to 99%. The JVM -Xmx does not cap it, so: small payload cap, short timeout, skip huge functions,
        // and check free RAM before each function. A function that fails is logged and skipped, never retried.
        final int TIMEOUT_S = 60, MAX_PAYLOAD_MB = 256;
        final long MAX_BODY_BYTES = 30000, MIN_FREE_RAM = 6L << 30;
        DecompInterface di = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        opts.setMaxPayloadMBytes(MAX_PAYLOAD_MB);
        di.setOptions(opts);
        di.openProgram(currentProgram);
        com.sun.management.OperatingSystemMXBean os =
            (com.sun.management.OperatingSystemMXBean) java.lang.management.ManagementFactory.getOperatingSystemMXBean();
        StringBuilder skipped = new StringBuilder();
        for (Function fn : todo) {
            String name = fn.getName(true).replace("::", "__").replaceAll("[^\\w]", "_");
            String file = name + "_" + fn.getEntryPoint() + ".c";
            long body = fn.getBody().getNumAddresses();
            String why = null;
            // never decompile these again: 0x5da490 (Entity_Effect::Update, ~200 KB) drove decompile.exe to 13.3 GB;
            // 0x6d4ce0 (Entity_NPC::HandleCollision) always fails. Read both with Probe dis: instead.
            String ep = fn.getEntryPoint().toString();
            if (ep.endsWith("5da490") || ep.endsWith("6d4ce0")) why = "on the never-decompile list; use Probe dis:";
            else if (body > MAX_BODY_BYTES) why ="too big (" + body + " bytes > " + MAX_BODY_BYTES + "); read it with Probe dis: instead";
            else if (os.getFreeMemorySize() < MIN_FREE_RAM) why = "free RAM below 6 GB (" + (os.getFreeMemorySize() >> 20) + " MB)";
            if (why != null) {
                skipped.append(fn.getEntryPoint()).append(' ').append(fn.getName(true)).append(": ").append(why).append('\n');
                Files.writeString(out.resolve(file), "// " + fn.getName(true) + " @ " + fn.getEntryPoint() + "\n// skipped: " + why + "\n");
                println("skipped " + file + ": " + why);
                continue;
            }
            DecompileResults r = di.decompileFunction(fn, TIMEOUT_S, monitor);
            String c = (r != null && r.decompileCompleted()) ? r.getDecompiledFunction().getC()
                                                             : "// decompile failed: " + (r == null ? "" : r.getErrorMessage());
            Files.writeString(out.resolve(file), "// " + fn.getName(true) + " @ " + fn.getEntryPoint() + "\n" + c);
            callees.append(fn.getName(true)).append(" @ ").append(fn.getEntryPoint()).append('\n');
            for (Function k : fn.getCalledFunctions(monitor))
                callees.append("    ").append(k.getEntryPoint()).append(' ').append(k.getName(true)).append('\n');
            println("wrote " + file);
        }
        di.dispose();
        Files.writeString(out.resolve("callees.txt"), callees.toString(), StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        if (skipped.length() > 0)
            Files.writeString(out.resolve("skipped.txt"), skipped.toString(), StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }

    Function findTarget(String t) {
        if (t.startsWith("0x")) {
            Address a = toAddr(Long.decode(t));
            Function f = getFunctionAt(a);
            return f != null ? f : getFunctionContaining(a);
        }
        for (Function f : currentProgram.getFunctionManager().getFunctions(true))
            if (f.getName(true).equals(t) || f.getName().equals(t)) return f;
        return null;
    }
}
