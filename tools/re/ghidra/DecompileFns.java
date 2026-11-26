// Decompile chosen functions of the analysed exe to C text files, for reading enemy AI.
// Arguments: <out_dir> <target> [<target> ...]
//   target = an address (0x4a1b20) or a name (Entity_NPC::Update)
//   prefix "npc:" first moves the function into the Entity_NPC class as __thiscall, so its first
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
            boolean npc = t.startsWith("npc:");
            if (npc) t = t.substring(4);
            String rename = null;
            if (t.contains("+")) { rename = t.substring(t.indexOf('+') + 1); t = t.substring(0, t.indexOf('+')); }
            Function fn = findTarget(t);
            if (fn == null) { println("not found: " + t); continue; }
            if (npc) {
                SymbolTable st = currentProgram.getSymbolTable();
                Namespace cls = st.getNamespace("Entity_NPC", currentProgram.getGlobalNamespace());
                if (cls == null) cls = st.createClass(currentProgram.getGlobalNamespace(), "Entity_NPC", SourceType.USER_DEFINED);
                fn.setParentNamespace(cls);
                fn.setCallingConvention("__thiscall");
            }
            if (rename != null) fn.setName(rename, SourceType.USER_DEFINED);
            todo.add(fn);
        }
        DecompInterface di = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        di.setOptions(opts);
        di.openProgram(currentProgram);
        for (Function fn : todo) {
            DecompileResults r = di.decompileFunction(fn, 300, monitor);
            String name = fn.getName(true).replace("::", "__").replaceAll("[^\\w]", "_");
            String file = name + "_" + fn.getEntryPoint() + ".c";
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
