#load "entity.jai";
#load "entity_iterators.jai";
#load "entity_views.jai";
#load "entity_array.jai";
#load "builtin_fragments.jai";
#load "replication.jai";

Entity_Plugin :: struct {
    #as using base: Metaprogram_Plugin;

    entity_types: [..] string;

    generated_entities: bool;
}

get_plugin :: () -> *Metaprogram_Plugin {
    p := New(Entity_Plugin);

    p.add_source    = add_source;
    p.message       = message;

    log("Initialized entity plugin");
    return p;
}

#scope_file

add_source :: (p: *Metaprogram_Plugin) {
    TO_INSERT :: #string DONE
        simple_entities :: #import "simple_entities";
        using simple_entities;
    DONE;

    w := p.workspace;
    assert(w >= 0);
    add_build_string(TO_INSERT, w);
}

message :: (p: *Metaprogram_Plugin, message: *Message) {
    entity_plugin := p.(*Entity_Plugin);
    using,except(message) entity_plugin;

    if message.kind == {
        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;
            for typechecked.structs {
                defined_type := it.expression.defined_type;
                if is_subclass_of(defined_type, "Entity") {
                    name := defined_type.name;
                    array_add_if_unique(*entity_plugin.entity_types, name);
                }
            }
        case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .TYPECHECKED_ALL_WE_CAN {
                if !generated_entities {
                    generate_entities(entity_plugin, message.workspace);
                    generated_entities = true;
                }
            }
    }
}

#scope_file

generate_entities :: (entity_plugin: *Entity_Plugin, w: Workspace) {
    INSERT_STRING :: #string DONE
    ENTITY_TYPES :: Type.[%1];
    #poke_name simple_entities ENTITY_TYPES;
    DONE

    quick_sort(entity_plugin.entity_types, compare_strings);

    type_names := join(..entity_plugin.entity_types, ", ");
    build_string := sprint(INSERT_STRING, type_names);

    entity_def_pokes: String_Builder;
    for entity_plugin.entity_types {
        print_to_builder(*entity_def_pokes, "#poke_name simple_entities %;", it);
    }
    add_build_string(builder_to_string(*entity_def_pokes), w);


    add_build_string(build_string, w);
}

#import "String";
#import "Sort";
#import "Compiler";