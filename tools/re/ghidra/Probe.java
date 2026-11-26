// Small lookups in the analysed exe, written to <out_dir>/probe.txt.
// Arguments: <out_dir> <command> [<command> ...]
//   xrefs:0xADDR      every place that references ADDR (code or data), with the containing function
//   dump:0xADDR:N     N dwords starting at ADDR, each with the function it points to (for vtables)
//   consts:0xVALUE    functions whose instructions use the scalar VALUE (e.g. an entity type)
// Why (2026-11-26, RE pilot): find the NPC Update through its vtable when a signature goes stale after a
// game update, and find which functions handle a given entity type.
// @category IsaacBot
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.*;
import java.nio.file.*;
import java.util.*;

public class Probe extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i < args.length; i++) {
            String[] p = args[i].split(":");
            sb.append("== ").append(args[i]).append('\n');
            if (p[0].equals("xrefs")) {
                for (Reference r : getReferencesTo(toAddr(Long.decode(p[1])))) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    sb.append(r.getFromAddress()).append(' ').append(r.getReferenceType())
                      .append(' ').append(f == null ? "-" : f.getName(true) + "@" + f.getEntryPoint()).append('\n');
                }
            } else if (p[0].equals("dump")) {
                Address a = toAddr(Long.decode(p[1]));
                int n = Integer.parseInt(p[2]);
                for (int k = 0; k < n; k++) {
                    Address at = a.add(4L * k);
                    long v = getInt(at) & 0xffffffffL;
                    Function f = getFunctionAt(toAddr(v));
                    sb.append(k).append(' ').append(at).append(" -> ").append(String.format("%08x", v))
                      .append(' ').append(f == null ? "" : f.getName(true)).append('\n');
                }
            } else if (p[0].equals("dis")) {
                // N instructions starting at ADDR
                Instruction ins = getInstructionAt(toAddr(Long.decode(p[1])));
                if (ins == null) ins = getInstructionAfter(toAddr(Long.decode(p[1])));
                for (int k = 0; ins != null && k < Integer.parseInt(p[2]); k++, ins = ins.getNext())
                    sb.append(ins.getAddress()).append(' ').append(ins).append('\n');
            } else if (p[0].equals("floats")) {
                // every instruction in the function that reads a 4-byte constant from memory, shown as a float
                Function fn = getFunctionContaining(toAddr(Long.decode(p[1])));
                for (Instruction ins : currentProgram.getListing().getInstructions(fn.getBody(), true)) {
                    for (Reference r : ins.getReferencesFrom()) {
                        if (!r.getReferenceType().isData()) continue;
                        try {
                            float fv = Float.intBitsToFloat(getInt(r.getToAddress()));
                            sb.append(ins.getAddress()).append(' ').append(ins).append("   ; ")
                              .append(r.getToAddress()).append(" = ").append(fv).append('\n');
                        } catch (Exception ex) { /* not readable memory */ }
                    }
                }
            } else if (p[0].equals("consts")) {
                long want = Long.decode(p[1]);
                Map<Function, Integer> hits = new LinkedHashMap<>();
                for (Instruction ins : currentProgram.getListing().getInstructions(true)) {
                    for (int o = 0; o < ins.getNumOperands(); o++)
                        for (Object obj : ins.getOpObjects(o))
                            if (obj instanceof Scalar && ((Scalar) obj).getUnsignedValue() == want) {
                                Function f = getFunctionContaining(ins.getAddress());
                                if (f != null) hits.merge(f, 1, Integer::sum);
                            }
                }
                for (Map.Entry<Function, Integer> e : hits.entrySet())
                    sb.append(e.getKey().getEntryPoint()).append(' ').append(e.getKey().getName(true))
                      .append(" uses=").append(e.getValue()).append(" size=").append(e.getKey().getBody().getNumAddresses()).append('\n');
            }
        }
        Path out = Paths.get(args[0]);
        Files.createDirectories(out);
        Files.writeString(out.resolve("probe.txt"), sb.toString());
    }
}
