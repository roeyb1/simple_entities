Entity_ID :: #type,distinct s32;
INVALID_ENTITY_ID: Entity_ID : 0;

Entity_Flags :: enum_flags u32 {
    NONE                    :: 0;
}

Entity :: struct {
    // The name of the entity
    name:           Name;
    // Unique identifier for this entity
    id:             Entity_ID;          @SyncOnce
    // Entity flags
    flags:          Entity_Flags;

    // Position of this entity in worldspace
    position:       Position;           @VisualInterp
    // Rotation of the entity
    rotation:       Rotation;           @VisualInterp
}

// call `as_base_entity` at compile time inside the body of every entity struct type to setup
// any relevant compile-time metadata on the struct
as_base_entity :: (entities_per_bucket: s64 = 16) -> string #compile_time {
    sb: String_Builder;
    sbprint(*sb, "#as using _base_entity: Entity;\n ENTITIES_PER_BUCKET :: %;\n", entities_per_bucket);
    return builder_to_string(*sb);
}

Entity_Manager :: struct {
    all:            [..] Dynamic_Entity_Handle;
    by_type:        Entity_Storage;
    next_id:        Entity_ID;
    allocator:      Allocator;
}

Entity_Storage :: struct {
    #insert -> string {
        sb: String_Builder;
        for ENTITY_TYPES {
            print_to_builder(*sb, "_%1: Entity_Array(%1, %1.ENTITIES_PER_BUCKET);\n", it);
        }
        return builder_to_string(*sb);
    }
}


Entity_Handle_Base :: struct(Entity_Type: Type) {
    // pointer to the entity manager which owns the pointed-to entity
    manager:            *Entity_Manager;
    // cached pointer to the entity
    #as using entity:   *Entity_Type;
    // where to find the entity in its type's storage.
    locator:            Entity_Locator;
    // id of the entity when the handle was created:
    entity_id:          Entity_ID;
}

Entity_Handle :: struct($Entity_Type: Type) {
    using base:     Entity_Handle_Base(Entity_Type);
}

Dynamic_Entity_Handle :: struct {
    using base:     Entity_Handle_Base(Entity);
    // dynamic type of this entity handle
    type:               Type;
}

Weak_Entity_Handle :: Dynamic_Entity_Handle;

operator == :: (a: Dynamic_Entity_Handle, b: Dynamic_Entity_Handle) -> bool {
    return a.entity == b.entity && a.entity_id == b.entity_id;
}

operator == :: (a: Dynamic_Entity_Handle, b: *Entity) -> bool #symmetric {
    return a.entity == b;
}

INVALID_ENTITY_HANDLE :: Dynamic_Entity_Handle.{};

//------------------------------ Spawning Entities ------------------------------ 

spawn_entity :: (using entity_manager: *Entity_Manager, $entity_type: Type, id: Entity_ID = 0) -> Entity_Handle(entity_type) {
    entity_id := ifx id == 0 then {
        next_id += 1; next_id;
    } else {
        id;
    }

    ptr, locator := alloc_entity(*by_type, entity_type, ifx id == 0 then next_id else id,, allocator);

    handle := make_handle(entity_manager, ptr, locator);
    handle.manager = entity_manager;
    handle.locator = locator;

    array_add(*all, make_dynamic(handle),, allocator);

    return handle;
}

spawn_entity_dynamic :: (using entity_manager: *Entity_Manager, entity_type: Type, id: Entity_ID = 0) -> Dynamic_Entity_Handle {
    #insert #run generate_switch_on_entity_type("entity_type", "return make_dynamic(spawn_entity(entity_manager, %1, id = id));\n");
    return .{};
}

alloc_entity :: (using entity_storage: *Entity_Storage, $entity_type: Type, id: Entity_ID) -> (*entity_type, Entity_Locator) {
    assert(entity_type.(*Type_Info).type == .STRUCT);

    array := array_for_entity_type(entity_storage, entity_type);

    locator, ptr := entity_array_add(array, .{});

    ptr.id = id;
    return ptr, locator;
}

alloc_entity_dynamic :: (entity_storage: *Entity_Storage, entity_type: Type, id: Entity_ID) -> *Entity {
    #insert #run generate_switch_on_entity_type("entity_type", "return alloc_entity(entity_storage, %1, id);\n");
    return null;
}

//------------------------------ Destroying Entities ------------------------------ 

// Default entity cleanup function. Will be called if no specific type override is implemented.
cleanup :: inline (entity: *Entity) {}

destroy_entity :: (using entity_manager: *Entity_Manager, entity: Entity_Handle) {
    array := array_for_entity_type(*entity_manager.by_type, entity.Entity_Type);

    cleanup(entity.entity);

    entity_array_remove(array, entity.locator);
    for all {
        if it.entity == entity.entity {
            remove it;
            break;
        }
    }
}

destroy_entity_dynamic :: (using entity_manager: *Entity_Manager, entity: Dynamic_Entity_Handle) {
    #insert #run generate_switch_on_entity_type("entity.type", "destroy_entity(entity_manager,  make_handle(entity, %1));\n");
}

//------------------------------ Copying Entities ------------------------------ 

copy_entity :: (dest: *$T/Entity, source: *T, no_copy_notes: [] string = .[]) {
    copy_entity(dest, source, T, no_copy_notes);
}

copy_entity :: (dest: *Entity, source: *Entity, entity_type: Type, no_copy_notes: [] string = .["NoSerialize"]) {
    assert(entity_type.(*Type_Info).type == .STRUCT);
    copy_entity_member(dest, source, entity_type.(*Type_Info_Struct), no_copy_notes);
}

//------------------------------ Entity Handles ------------------------------ 

make_handle :: (entity_manager: *Entity_Manager, entity: *$Entity_Type/Entity, locator: Entity_Locator) -> Entity_Handle(Entity_Type) {
    return .{.{entity_manager, entity, locator, entity.id}};
}

make_handle :: (dynamic_handle: Dynamic_Entity_Handle, $Entity_Type: Type) -> Entity_Handle(Entity_Type) {
    assert(dynamic_handle.type == Entity_Type, "Attempted to create a strongly typed entity handle from a weak handle of an incompatible entity type! (from % to %)", dynamic_handle.type, Entity_Type);
    // It is safe to cast the base of the entity handle into the passed in entity type as we've asserted they are compatible.
    return .{ base = cast,force (Entity_Handle_Base(Entity_Type)) dynamic_handle.base };
}

make_dynamic_handle :: (entity_manager: *Entity_Manager, entity: *$Entity_Type/Entity, locator: Entity_Locator) -> Dynamic_Entity_Handle {
    return .{.{entity_manager, entity, locator, entity.id}, Entity_Type};
}

make_dynamic :: (handle: Entity_Handle) -> Dynamic_Entity_Handle {
    return .{ type = handle.Entity_Type, base = cast,force (Entity_Handle_Base(Entity)) handle.base };
}

resolve :: (handle: *Entity_Handle) -> bool, *handle.Entity_Type {
    if handle.entity_id == INVALID_ENTITY_ID then return false, null;

    array := array_for_entity_type(*handle.manager.by_type, handle.Entity_Type);
    is_valid_entity := entity_array_is_entry(array, handle.locator);

    if is_valid_entity {
        entity := entity_array_find_pointer(array, handle.locator);
        if entity.id == handle.entity_id {
            handle.entity = entity;
            return true, entity;
        }
    }

    handle.entity = null;
    return false, null;
}

resolve :: (handle: *Dynamic_Entity_Handle) -> bool, *Entity {
    PER_ENTITY_TYPE_STRING :: #string DONE
        success, entity: = resolve(*make_handle(handle, %1));
        handle.entity = entity;
        return success, entity;
    DONE

    #insert #run generate_switch_on_entity_type("handle.type", PER_ENTITY_TYPE_STRING);

    return false, null;
}

// Returns an entity handle pointing to the entity with the specified entity id.
// #TODO: This should be possible to make much faster. Right now it just does a linear search.
get :: (using entity_manager: *Entity_Manager, entity_id: Entity_ID) -> bool, Dynamic_Entity_Handle {
    for all {
        if it.entity_id == entity_id then return true, it;
    }
    return false, INVALID_ENTITY_HANDLE;
}

free_manager :: (using entity_manager: *Entity_Manager) {
    // #todo: arenas
    //if arena then free_arena(arena);
}

free_storage :: (using storage: *Entity_Storage) {
    #insert -> string {
        sb: String_Builder;
        for member : type_info(Entity_Storage).members {
            sbprint(*sb, "for % cleanup(it);\n", member.name);
            sbprint(*sb, "entity_array_reset(*%);\n", member.name);
        }
        return builder_to_string(*sb);
    }
}

generate_switch_on_entity_type :: (entity_type_string: string, insert_string: string) -> string {
    sb: String_Builder;
    sbprint(*sb, "if % == {\n", entity_type_string);
    for type : ENTITY_TYPES {
        type_string := type.(*Type_Info_Struct).name;
        sbprint(*sb, "\tcase %1;\n", type_string);
        sbprint(*sb, "\t\t");
        sbprint(*sb, insert_string, type_string);
    }
    sbprint(*sb, "}\n");
    return builder_to_string(*sb);
}

array_for_entity_type :: (using entity_manager: *Entity_Storage, $entity_type: Type) -> *Entity_Array(entity_type, entity_type.ENTITIES_PER_BUCKET) {
    #insert -> string {
        return sprint("return *_%1;\n", entity_type.(*Type_Info_Struct).name);
    }
}

#scope_file

copy_entity_member :: (dst: *void, src: *void, ti: *Type_Info, no_copy_notes: [] string) {
    if ti.type == {
        case .BOOL; #through ;
        case .INTEGER; #through;
        case .FLOAT; #through;
        case .ENUM;
            memcpy(dst, src, ti.runtime_size);
        case .STRING;
            dst_str: *string = cast(*string) dst;
            // this will be terrible if the data is not properly zero-initialized:
            if dst_str.data != null { free(dst_str); }
            dst_str.* = copy_string(src.(*string).*);
        case .ARRAY;
            // #todo:
            assert(false);
        case .STRUCT;
            struct_info := cast(*Type_Info_Struct) ti;
            last_offset := 0;
            for member : struct_info.members {
                if member.flags & .CONSTANT             then continue;
                if member.offset_in_bytes < last_offset then continue;
                if has_any_note(member, no_copy_notes)  then continue;
                last_offset = member.offset_in_bytes;

                copy_entity_member(dst + member.offset_in_bytes, src + member.offset_in_bytes, member.type, no_copy_notes);
            }
        case .VARIANT;
            v_info := ti.(*Type_Info_Variant).variant_of;
            copy_entity_member(dst, src, v_info, no_copy_notes);
        case .POINTER;
            // #TODO: handle deep vs shallow copy
            assert(false);
        case;
            assert(false);
    }
} @NoProfile


#scope_module 

sbprint :: print_to_builder;

has_any_note :: (ti: Type_Info_Struct_Member, notes: [] string) -> bool {
    for note : notes for ti.notes  if it == note  return true;
    return false;
}

#import "Basic";
#import "Math";
#import "Xar";
