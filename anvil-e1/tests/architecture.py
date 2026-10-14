"""Authoritative geometry, packing and elaboration gates."""
import json
import re
from pathlib import Path

from model import Geometry, CONFIGS, inventory

DEFAULT = Geometry(262144,512,512,2048,768,24,4,2,1,256,512,512,262144)


def verify_architecture(execution):
    root = Path(".")
    config = json.loads((root/"hf_embeddinggemma2_spec/config.json").read_text())
    c = config["text_config"]
    assert config["model_type"] == "embedding_gemma2_text"
    mapping = {"vocab_size":DEFAULT.V,"hidden_size":DEFAULT.H,
        "hidden_size_per_layer_input":DEFAULT.P,"intermediate_size":DEFAULT.I,
        "embedding_dim":DEFAULT.E,"num_hidden_layers":DEFAULT.L,
        "num_attention_heads":DEFAULT.QH,"num_key_value_heads":DEFAULT.LK,
        "head_dim":DEFAULT.LD,"sliding_window":DEFAULT.W,
        "max_position_embeddings":DEFAULT.S}
    for n,v in mapping.items():
        assert c[n] == v, (n,c[n],v)
    assert c["hidden_activation"] == "gelu_pytorch_tanh"
    assert c["rms_norm_eps"] == 1e-6 and c["attention_bias"] is False
    assert c["attention_dropout"] == 0
    assert (c["bos_token_id"],c["eos_token_id"],c["pad_token_id"]) == (2,1,0)
    assert c["layer_types"] == [
        "full_attention" if l%6==5 else "sliding_attention" for l in range(24)]
    assert set(c["per_layer_config"]) == {"05","11","17","23"}
    assert all(v == {"head_dim":512,"num_key_value_heads":1}
               for v in c["per_layer_config"].values())
    assert c["rope_parameters"]["sliding_attention"]["rope_theta"] == 10000
    assert c["rope_parameters"]["full_attention"]["rope_theta"] == 1000000
    manifest = json.loads((root/"hf_embeddinggemma2_spec/language_model_tensors.json").read_text())
    expanded = dict(manifest["global_tensors"])
    for layer in range(24):
        prefix = 5 if layer%6==5 else 0
        key = "full_attention_layer_template_layer_5" if prefix==5 else (
            "sliding_attention_layer_template_layer_0")
        for name,value in manifest[key].items():
            expanded[name.replace(f"layers.{prefix}.",f"layers.{layer}.")] = value
    entries = inventory(DEFAULT)
    assert len(entries) == len(expanded) == manifest["total_language_model_tensors"] == 413
    assert {e["name"]:e["shape"] for e in entries} == {
        n:v["shape"] for n,v in expanded.items()}
    assert all(v["dtype"]=="BF16" for v in expanded.values())
    modules = json.loads((root/"hf_embeddinggemma2_spec/modules.json").read_text())
    assert [m["idx"] for m in modules] == [0,1,2]
    assert [m["type"].split(".")[-1] for m in modules] == ["Transformer","Pooling","Normalize"]
    pooling = json.loads((root/"hf_embeddinggemma2_spec/1_Pooling/config.json").read_text())
    assert pooling == {"embedding_dimension":768,"pooling_mode":"mean","include_prompt":True}
    sentence = json.loads((root/"hf_embeddinggemma2_spec/sentence_bert_config.json").read_text())
    assert sentence["modality_config"]["text"] == {
        "method":"forward","method_output_name":"last_hidden_state"}
    assert sentence["module_output_name"] == "token_embeddings"
    sources = sorted(root.glob("rtl/*.sv"))
    names = []
    for p in sources:
        found = re.findall(r"^\s*module\s+(\w+)",p.read_text(),re.M)
        assert found == [p.stem], (str(p),found)
        names += found
    for suffix in ("top","controller","memory","mac","nonlinear","norm","attention","pool"):
        assert "anvil_e1_"+suffix in names
    top = (root/"rtl/anvil_e1_top.sv").read_text()
    for n,v in DEFAULT.parameters().items():
        assert re.search(r"\b"+n+r"\s*=\s*"+str(v)+r"\b",top), (n,v)
    assert not any(re.search(r"\b(real|shortreal|DPI)\b",p.read_text()) for p in sources)
    execution.run("default-elaboration",["iverilog","-g2012","-t","null",
        "-s","anvil_e1_top"]+[str(p) for p in sources])
    for name,value in (("HIDDEN_SIZE",0),("LOCAL_KV_HEADS",0),
            ("NUM_Q_HEADS",3),("LOCAL_HEAD_DIM",3),("EMBEDDING_DIM",7),
            ("SLIDING_WINDOW",0),("MAX_SEQ_LEN",0)):
        binary = execution.output/f"invalid-{name}.vvp"
        overrides = CONFIGS["A"].parameters()
        if name == "NUM_Q_HEADS":
            overrides["LOCAL_KV_HEADS"] = 2
        overrides[name] = value
        execution.run("invalid-compile-"+name,["iverilog","-g2012","-s","anvil_e1_top",
            "-o",str(binary)]+[f"-Panvil_e1_top.{n}={v}" for n,v in overrides.items()]+
            [str(p) for p in sources])
        log = execution.run("invalid-run-"+name,["vvp",str(binary)],expected_exit=1)
        assert "PARAMETER ERROR" in log.read_text(), name
    from packing import verify_packing
    from addresses import verify_addresses
    verify_packing(execution)
    verify_addresses(execution)
    (execution.output/"architecture-summary.json").write_text(json.dumps({
        "expanded_tensors":413,"full_layers":[5,11,17,23],
        "default_weights_bytes":sum(e["size_bytes"] for e in entries),
        "rtl_modules":names,"invalid_parameters_checked":7},indent=2)+"\n")
