// Apply REPENTOGON's function signatures and struct field offsets to an analysed isaac-ng.exe.
// Input: sigs.tsv and fields.tsv made by tools/re/zhl_extract.py (pass their folder as the script argument).
// Why (2026-11-26, RE pilot): names and typed fields make the decompiled enemy AI readable.
// A signature is applied only when it matches exactly one place in executable memory.
// @category IsaacBot
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class ApplyZhl extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Path dir = Paths.get(args.length > 0 ? args[0] : askDirectory("zhl tables", "Use").getAbsolutePath());
        StringBuilder report = new StringBuilder();
        applyFields(dir.resolve("fields.tsv"), report);
        applySigs(dir.resolve("sigs.tsv"), report);
        Files.writeString(dir.resolve("apply_report.txt"), report.toString());
        println("ApplyZhl done; report in " + dir.resolve("apply_report.txt"));
    }

    // ---- signatures -------------------------------------------------------------------------
    void applySigs(Path tsv, StringBuilder report) throws Exception {
        Memory mem = currentProgram.getMemory();
        List<MemoryBlock> exec = new ArrayList<>();
        for (MemoryBlock b : mem.getBlocks()) if (b.isExecute() && b.isInitialized()) exec.add(b);
        int ok = 0, none = 0, multi = 0;
        for (String line : Files.readAllLines(tsv)) {
            if (monitor.isCancelled()) break;
            String[] p = line.split("\t");
            if (p.length < 2) continue;
            String hex = p[0].replace("(", "").replace(")", "");
            if (hex.length() < 8 || hex.length() % 2 != 0) continue;
            int n = hex.length() / 2;
            byte[] bytes = new byte[n], mask = new byte[n];
            for (int i = 0; i < n; i++) {
                String b = hex.substring(2 * i, 2 * i + 2);
                if (b.equals("??")) { bytes[i] = 0; mask[i] = 0; }
                else { bytes[i] = (byte) Integer.parseInt(b, 16); mask[i] = (byte) 0xff; }
            }
            List<Address> hits = new ArrayList<>();
            for (MemoryBlock b : exec) {
                Address a = b.getStart();
                while (a != null && hits.size() < 2) {
                    Address f = mem.findBytes(a, b.getEnd(), bytes, mask, true, monitor);
                    if (f == null) break;
                    hits.add(f);
                    a = f.next();
                }
            }
            if (hits.isEmpty()) { none++; report.append("NONE\t").append(p[1]).append('\n'); continue; }
            if (hits.size() > 1) { multi++; report.append("MULTI\t").append(p[1]).append('\n'); continue; }
            Address at = hits.get(0);
            Function fn = getFunctionAt(at);
            if (fn == null) {
                disassemble(at);
                fn = createFunction(at, null);
            }
            if (fn == null) { report.append("NOFUNC\t").append(p[1]).append('\t').append(at).append('\n'); continue; }
            setName(fn, p[1]);
            ok++;
            report.append("OK\t").append(p[1]).append('\t').append(at).append('\n');
        }
        report.insert(0, "signatures: applied " + ok + ", no match " + none + ", ambiguous " + multi + "\n");
        println("signatures: applied " + ok + ", no match " + none + ", ambiguous " + multi);
    }

    void setName(Function fn, String qualified) throws Exception {
        String[] parts = qualified.split("::");
        Namespace ns = currentProgram.getGlobalNamespace();
        SymbolTable st = currentProgram.getSymbolTable();
        for (int i = 0; i < parts.length - 1; i++) {
            Namespace next = st.getNamespace(parts[i], ns);
            if (next == null) next = st.createClass(ns, parts[i], SourceType.IMPORTED);
            ns = next;
        }
        fn.setParentNamespace(ns);
        fn.setName(parts[parts.length - 1], SourceType.IMPORTED);
        if (parts.length > 1 && fn.getCallingConventionName().equals("__thiscall") == false
                && fn.getCallingConventionName().equals("unknown")) {
            fn.setCallingConvention("__thiscall");
        }
    }

    // ---- struct fields ----------------------------------------------------------------------
    Map<String, Map<Long, String[]>> readFields(Path tsv) throws IOException {
        Map<String, Map<Long, String[]>> out = new LinkedHashMap<>();
        for (String line : Files.readAllLines(tsv)) {
            String[] p = line.split("\t");
            if (p.length < 4) continue;
            out.computeIfAbsent(p[0], k -> new TreeMap<>()).put(Long.decode(p[1]), new String[]{p[2], p[3]});
        }
        return out;
    }

    DataType typeFor(String t, DataTypeManager dtm, DataType vector) {
        String s = t.replace("const", "").trim();
        if (s.endsWith("*")) return PointerDataType.dataType;
        switch (s) {
            case "int": case "int32_t": case "signed int": return IntegerDataType.dataType;
            case "unsigned int": case "uint32_t": case "unsigned long": return UnsignedIntegerDataType.dataType;
            case "float": return FloatDataType.dataType;
            case "bool": return BooleanDataType.dataType;
            case "uint8_t": case "unsigned char": case "char": return ByteDataType.dataType;
            case "short": case "int16_t": return ShortDataType.dataType;
            case "uint16_t": case "unsigned short": return UnsignedShortDataType.dataType;
            case "unsigned long long": case "uint64_t": return UnsignedLongLongDataType.dataType;
            case "Vector": return vector;
            case "EntityPtr": return PointerDataType.dataType;
            default: return null;
        }
    }

    void applyFields(Path tsv, StringBuilder report) throws Exception {
        DataTypeManager dtm = currentProgram.getDataTypeManager();
        StructureDataType v = new StructureDataType("Vector", 0);
        v.add(FloatDataType.dataType, "X", null);
        v.add(FloatDataType.dataType, "Y", null);
        DataType vector = dtm.addDataType(v, DataTypeConflictHandler.REPLACE_HANDLER);
        Map<String, Map<Long, String[]>> all = readFields(tsv);
        // Entity subclasses carry the Entity fields too (offsets are absolute in the .zhl files).
        String[][] build = {{"Entity", "Entity", "0x410"}, {"Entity_NPC", "Entity", "0xf60"},
                            {"Entity_Player", "Entity", "0x4000"}, {"Entity_Projectile", "Entity", "0x600"}};
        for (String[] b : build) {
            Map<Long, String[]> f = new TreeMap<>();
            if (!b[0].equals(b[1]) && all.containsKey(b[1])) f.putAll(all.get(b[1]));
            if (all.containsKey(b[0])) f.putAll(all.get(b[0]));
            long size = Long.decode(b[2]);
            for (Long off : f.keySet()) size = Math.max(size, off + 16);
            StructureDataType s = new StructureDataType(b[0], (int) size);
            int placed = 0;
            for (Map.Entry<Long, String[]> e : f.entrySet()) {
                DataType dt = typeFor(e.getValue()[0], dtm, vector);
                if (dt == null) continue;
                String name = e.getValue()[1].replaceFirst("^_", "");
                try { s.replaceAtOffset(e.getKey().intValue(), dt, dt.getLength(), name, e.getValue()[0]); placed++; }
                catch (Exception ex) { report.append("FIELDSKIP\t").append(b[0]).append('.').append(name).append('\n'); }
            }
            dtm.addDataType(s, DataTypeConflictHandler.REPLACE_HANDLER);
            report.append("struct ").append(b[0]).append(": ").append(placed).append(" fields\n");
        }
    }
}
