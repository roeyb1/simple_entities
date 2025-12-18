each_entity_with :: (entities: *Entity_Manager, $types: ..Type) -> Fragment_Iter(types) {
    return .{ entities = entities };
}

for_expansion :: (iter: Fragment_Iter, body: Code, flags: For_Flags) #expand {
    `it_index := 0;
    `it: Entity_View(iter.types) = ---;

    #insert -> string {
        sb: String_Builder;
        for ENTITY_TYPES {
            has_all, names := entity_type_has_all(it, iter.types);
            if has_all {
                sbprint(*sb, "for entity, index : iter.entities.by_type._% {\n", it);
                sbprint(*sb, "`it._entity = make_dynamic_handle(iter.entities, entity, index);\n");
                for 0..iter.types.count-1 {
                    sbprint(*sb, "`it._% = *entity.%;\n", iter.types[it], names[it]);
                }
                sbprint(*sb, "#insert body;");
                sbprint(*sb, "it_index += 1;");
                sbprint(*sb, "}\n", it);
            }
        }
        return builder_to_string(*sb);
    }
}

Fragment_Iter :: struct(types: [] Type) {
    entities: *Entity_Manager;
}

Entity_View :: struct(types: [] Type) {
    // Debug entity pointer. Useful to be able to inspect the full state of the current entity.
    _entity: Dynamic_Entity_Handle;

    #insert -> string {
        sb: String_Builder;
        for type : types {
            sbprint(*sb, "_%1: *%1;\n", type);
        }
        return builder_to_string(*sb);
    }
}

get_fragment :: (entity: Dynamic_Entity_Handle, $type: Type) -> *type {
    offset := get_member_offset(entity.type.(*Type_Info_Struct), type.(*Type_Info));
    if offset != -1 {
        return (entity.entity.(*u8) + offset).(*type);
    }
    return null;
}

#scope_file

entity_type_has_all :: (entity_type: Type, types: [] Type) -> bool, [] string {
    entity_ti := cast (*Type_Info_Struct) entity_type;
    assert(entity_ti.type == .STRUCT);

    results: [..] string;
    results.allocator = temp;

    for type : types {
        has_type := false;

        for entity_ti.members {
            found, name := member_has_type(it, cast (*Type_Info) type);
            if found {
                has_type = true;
                array_add(*results, name);
                break;
            }
        }

        if !has_type then return false, .[];
    }

    return true, results;
}

member_has_type :: (ti: Type_Info_Struct_Member, target: *Type_Info) -> bool, string {
    #import "Compiler";
    if ti.type == target || is_subclass_of(ti.type, target.(*Type_Info_Struct).name) {
        return true, ti.name;
    }

    if ti.flags & .AS == .AS {
        // if the member is #as, then it must be a struct and is safe to cast to struct
        for member : ti.type.(*Type_Info_Struct).members {
            found, name := member_has_type(member, target);
            if found {
                return found, name;
            }
        }
    }
    return false, "";
}

get_member_offset :: (ti: Type_Info_Struct, target: *Type_Info) -> s64 {
    get_member_offset :: (ti: Type_Info_Struct_Member, target: *Type_Info) -> s64 {
        #import "Compiler";
        if ti.type == target || is_subclass_of(ti.type, target.(*Type_Info_Struct).name) {
            return ti.offset_in_bytes;
        }

        if test_flag_bit(ti.flags, .AS) {
            // if the member is #as, then it must be a struct and is safe to cast to struct
            for member : ti.type.(*Type_Info_Struct).members {
                offset := get_member_offset(member, target);
                if offset {
                    return offset;
                }
            }
        }
        return -1;
    }

    for member : ti.members {
        offset := get_member_offset(member, target);
        if offset != -1 {
            return offset;
        }
    }
    return -1;
}
