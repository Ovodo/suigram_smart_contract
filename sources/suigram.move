#[allow(unused_field, unused_use)]
module suigram::suigram {
    /* Dependencies */
    use sui::random::{Self,Random};
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use std::string;
    use sui::url::{Self, Url};
    use std::debug::print;
    use sui::event;

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::test_utils::assert_eq;

    /* Error Codes - CONSTANTS */
    const EUSER_NOT_FOUND: u64 = 1;
    // const EMEME_NOT_FOUND: u64 = 2;
    const EUSER_ALREADY_FOLLOWING: u64 = 3;
    const EUSER_NOT_FOLLOWING: u64 = 4;
    const INSUFFICIENT_FUNDS: u64 = 5;
    // const ETheGramIsBroke: u64 = 6;
    const NOT_YOUR_MEME: u64 = 7;
    const USER_ALREADY_LIKED: u64 = 8;
    const USER_ALREADY_DISLIKED: u64 = 9;

    /* Structs */
    public struct TheGram has key {
        id: UID,
        memes: vector<Meme>,
        users: Table<address, User>,
        funding:Balance<SUI>
    }

    public struct Meme has store {
        id: ID,
        creator: address,
        tags: vector<string::String>,
        url: Url,
        title: vector<u8>,
        cash: Balance<SUI>,
        likes: vector<address>,
        dislikes: vector<address>,
        gifts: Balance<SUI>,
    }

    public struct User has store {
        user_address:address,
        username: vector<u8>,
        followers: vector<address>,
        following: vector<address>,
        tag_following: vector<vector<u8>>,
    }

    public struct WithdrawalCapability has key {
        id: UID,
        meme: ID,
    }

    /* Event Structs */
    public struct MemeCreated has copy, drop {
        id: ID,
    }
    public struct UserLiked has copy, drop {
        meme: ID,
        user: address,
    }
    public struct FollowedUser has copy, drop {
        user: address,
        follower: address,
    }
    public struct UnFollowed has copy, drop {
        user: address,
        unfollower: address,
    }
    public struct GiftedMeme has copy, drop {
        user: address,
        unfollower: address,
    }
    public struct UserDisliked has copy, drop {
        meme: ID,
        user: address,
    }
    public struct CashWithdrawal has copy, drop {
        meme: ID,
        amount: u64,
        recipient: address,
    }

    /* Functions */

    /*
        Initializes the TheGram application.
        @param ctx - The transaction context
    */
    fun init(ctx: &mut TxContext) {
        let coin = coin::mint_for_testing<SUI>(1_000_000_000_000,ctx);
        let funding = coin::into_balance(coin);
        let app = TheGram {
            id: object::new(ctx),
            memes: vector::empty<Meme>(),
            users: table::new(ctx),
            funding
        };
        transfer::share_object(app);
    }

    /*
        Creates a new user for TheGram.
        @param the_gram - The global shared object representing the SuiGram App
        @param user_address - The address of the new user to be added to the app
    */
    public fun createUser(the_gram: &mut TheGram, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let new_user = User {
            user_address :sender ,
            username: vector::empty<u8>(),
            followers: vector::empty<address>(),
            following: vector::empty<address>(),
            tag_following: vector::empty(),
        };
        table::add(&mut the_gram.users, sender, new_user);
    }

    /*
        Creates a new Meme in TheGram.
        @param ctx - The transaction context
        @param creator - The address of the creator
        @param tags - The tags to be added to the meme
        @param url - URL to locate and derive the image off-chain
        @param the_gram - The global shared object representing the SuiGram App
        @param title - The title/caption for the meme
    */
    #[allow(lint(public_random))]
    public fun createMeme(r:&Random, ctx: &mut TxContext, tags: vector<string::String>, url: vector<u8>, the_gram: &mut TheGram, title: vector<u8>) {
        if (!table::contains(&the_gram.users,tx_context::sender(ctx) )) {
            abort EUSER_NOT_FOUND
        };
        let mut random_generator = random::new_generator(r,ctx);
        let random_bytes = random::generate_bytes(&mut random_generator, 32);
        let new_meme = Meme {
            id: object::id_from_bytes(random_bytes),
            creator: tx_context::sender(ctx),
            tags,
            url: url::new_unsafe_from_bytes(url),
            title,
            cash: balance::zero<SUI>(),
            likes: vector::empty(),
            dislikes: vector::empty(),
            gifts: balance::zero<SUI>(),
        };
        event::emit(MemeCreated {
            id: new_meme.id,
        });
        vector::push_back(&mut the_gram.memes, new_meme);
    }

    /*
        Likes a meme.
        @param meme - The meme to like
        @param user - The address of the user liking the meme
    */
    public fun like(the_gram:&mut TheGram,meme_id:ID, ctx:&mut TxContext) {
        let length = vector::length(&the_gram.memes);
        let sender = tx_context::sender(ctx);
        
        let mut i = 0;
        while(i < length) {
            let meme = vector::borrow_mut(&mut the_gram.memes,i);
            if(meme.id == meme_id){
                assert!(!vector::contains(&meme.likes,&sender),USER_ALREADY_LIKED);
                vector::push_back(&mut meme.likes, sender);
                let sui_per_like = 50_000_000;
                let bal = balance::split(&mut the_gram.funding,sui_per_like);
                balance::join(&mut meme.cash, bal);
                event::emit(UserLiked {
                    meme: meme_id,
                    user: sender,
                });
            };
        i = i+1;
        };

    }

    /*
        Dislikes a meme.
        @param meme - The meme to dislike
        @param user - The address of the user disliking the meme
    */
    public fun dislike(meme: &mut Meme, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(!vector::contains(&meme.dislikes,&sender),USER_ALREADY_DISLIKED);
        vector::push_back(&mut meme.dislikes, sender);
        event::emit(UserDisliked {
            meme: meme.id,
            user:sender,
        });
    }

    /*
        Follows another user.
        @param user - The user to follow
        @param follower - The user who is following
    */
    public fun follow(user: &mut User, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        if (vector::contains(&user.followers, &sender)) {
            abort EUSER_ALREADY_FOLLOWING
        };
        vector::push_back(&mut user.followers, sender);
        event::emit(FollowedUser {
            user: user.user_address,
            follower:sender,
        });
    }

    /*
        Unfollows another user.
        @param user - The user to unfollow
        @param unfollower - The user who is unfollowing
    */
    public fun unfollow(user: &mut User, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);

        if (!vector::contains(&user.followers, &sender)) {
            abort EUSER_NOT_FOLLOWING
        };
        let (_,index) = vector::index_of(&user.followers, &sender);
        vector::remove(&mut user.followers, index);
        event::emit(UnFollowed {
            user: user.user_address,
            unfollower:sender
        });
    }

    /*
        Withdraws cash from a meme's balance.
        @param meme - The meme from which to withdraw
        @param cap - The withdrawal capability
        @param amount - The amount to withdraw
        @param recipient - The recipient of the withdrawn amount
    */
    public fun withdraw(meme: &mut Meme,ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        if (meme.creator != sender) {
            abort NOT_YOUR_MEME
        };
        if (balance::value(&meme.cash) == 0) {
            abort INSUFFICIENT_FUNDS
        };
        let bal = balance::withdraw_all(&mut meme.cash);
        let coin = coin::from_balance(bal,ctx);
        let amount = coin::value(&coin);
        transfer::public_transfer(coin, meme.creator);
        event::emit(CashWithdrawal {
            meme: meme.id,
            amount,
            recipient:sender,
        });
    }

    /* Helper function to find the index of a meme in the memes vector */
    // fun find_meme_index(memes: &vector<Meme>, id:UID): u64 {
    //     let mut i: u64 = 0;
    //     while (i < vector::length(memes)) {
    //         let meme = vector::borrow(memes, i);
    //         if (*meme.id == id) {
    //             return i
    //         };
    //         i = i + 1;
    //     };
    //     abort EMEME_NOT_FOUND
    // }

    /* Tests */

    #[test]
    fun test_init_success() {
        let module_owner = @0xa;
        let mut scenario_val = test_scenario::begin(module_owner);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            let tx = test_scenario::next_tx(scenario, module_owner);
            let expected_shared_objects = 1;
            let expected_created_objects = 1;
            assert_eq(
                vector::length(&test_scenario::created(&tx)),
                expected_created_objects
            );
            assert_eq(
                vector::length(&test_scenario::shared(&tx)),
                expected_shared_objects
            );
            let app = test_scenario::take_shared<TheGram>(scenario);
            assert_eq(
                balance::value(&app.funding),
                1000_000_000_000
            );
            test_scenario::return_shared(app);
        };
     
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_create_user() {
        let module_owner = @0xa;
        let user = @0xb;
        let mut scenario_val = test_scenario::begin(module_owner);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, user);
        let expected_no_users = 1;
        {
            let mut the_gram = test_scenario::take_shared<TheGram>(scenario);
            createUser(&mut the_gram, test_scenario::ctx(scenario));
            assert_eq(table::length(&the_gram.users), expected_no_users);
            test_scenario::return_shared(the_gram);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_create_meme() {
        let module_owner = @0x0;
        let user = @0xb;
        let expected_no_memes = 1;
        let mut scenario = test_scenario::begin(module_owner);
        {
            init(scenario.ctx());
        };
        random::create_for_testing(scenario.ctx());
        scenario.next_tx(user);
        {
            let mut the_gram = scenario.take_shared<TheGram>();
            let random_state = scenario.take_shared<Random>();
            createUser(&mut the_gram, scenario.ctx());
            let title = b"When you don't love me anymore";
            let funny = string::utf8(b"funny");
            let happy = string::utf8(b"happy");
            let pepe = string::utf8(b"pepe");
            let tags = vector[funny, happy, pepe];
            let ctx = scenario.ctx();
            createMeme(&random_state,ctx, tags, b"nice_image", &mut the_gram, title);
            assert_eq(vector::length(&the_gram.memes), expected_no_memes);
            test_scenario::return_shared(the_gram); 
            test_scenario::return_shared(random_state); 
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 1)
    }

    #[test]
    fun test_like_meme() {
        let module_owner = @0x0;
        let user = @0xb;
        let mut scenario = test_scenario::begin(module_owner);
        {
            init(scenario.ctx());
        };
        random::create_for_testing(scenario.ctx());
        scenario.next_tx(user);
        let mut the_gram = scenario.take_shared<TheGram>(); 
        let random_state = scenario.take_shared<Random>(); 
        let mut gen = random::new_generator(&random_state,scenario.ctx());
        let rand_bytes = random::generate_bytes(&mut gen,32);
        let mut _meme_id = object::id_from_bytes(rand_bytes);
        {
            createUser(&mut the_gram, scenario.ctx());
            let title = b"Funny meme";
            let tags = vector[string::utf8(b"funny")];
            let ctx = scenario.ctx();
            createMeme(&random_state,ctx, tags, b"nice_image", &mut the_gram, title);
            let meme = vector::borrow_mut(&mut the_gram.memes, 0);
            _meme_id = meme.id;
            };
            {
            like( &mut the_gram,_meme_id,scenario.ctx());
            };
            {
            let meme = vector::borrow_mut(&mut the_gram.memes, 0);
            assert_eq(vector::length(&meme.likes), 1);
            assert_eq(balance::value(&meme.cash),50_000_000);
            test_scenario::return_shared<TheGram>(the_gram);
            test_scenario::return_shared<Random>(random_state);
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 2);
    }

    #[test]
    fun test_dislike_meme() {
        let module_owner = @0x0;
        let user = @0xb;
        let mut scenario = test_scenario::begin(module_owner);
        {
            init(scenario.ctx());
        };
        random::create_for_testing(scenario.ctx());
        scenario.next_tx(user);
        {
            let mut the_gram = scenario.take_shared<TheGram>();
            let random_state = scenario.take_shared<Random>();
            let ctx = scenario.ctx();
            createUser(&mut the_gram,ctx );
            let title = b"Not so funny meme";
            let tags = vector[string::utf8(b"notfunny")];
            let ctx = scenario.ctx();
            createMeme(&random_state,ctx, tags, b"not_so_nice_image", &mut the_gram, title);
            let meme = vector::borrow_mut(&mut the_gram.memes, 0);
            dislike(meme, ctx);
            assert_eq(vector::length(&meme.dislikes), 1);
            test_scenario::return_shared(the_gram);
            test_scenario::return_shared(random_state);
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 2);
    }

    #[test]
    fun test_follow_user() {
        let module_owner = @0x0;
        let user1 = @0xb;
        let user2 = @0xc;
        let mut scenario = test_scenario::begin(module_owner);
        {
            init(scenario.ctx());
        };
        scenario.next_tx(user1);
        let mut the_gram = scenario.take_shared<TheGram>();
        {
            createUser(&mut the_gram, scenario.ctx());
        };
        scenario.next_tx(user2);
        {
            createUser(&mut the_gram, scenario.ctx());
            let user1_data = table::borrow_mut(&mut the_gram.users, user1);
            follow(user1_data, scenario.ctx());
            assert_eq(vector::length(&user1_data.followers), 1);
            test_scenario::return_shared(the_gram);
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 1);
    }

    #[test]
    fun test_unfollow_user() {
        let module_owner = @0xa;
        let user1 = @0xb;
        let user2 = @0xc;
        let mut scenario = test_scenario::begin(module_owner);

        {
            init(scenario.ctx());
        };
        scenario.next_tx(user1);
        let mut the_gram = scenario.take_shared<TheGram>();
        {
            createUser(&mut the_gram, scenario.ctx());
        };
        scenario.next_tx(user2);
        {

            createUser(&mut the_gram, scenario.ctx());
            let user1_data = table::borrow_mut(&mut the_gram.users, user1);
            follow( user1_data, scenario.ctx());
            unfollow(user1_data, scenario.ctx());
            assert_eq(vector::length(&user1_data.followers), 0);
            test_scenario::return_shared(the_gram);
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 2);
    }

    #[test]
    fun test_withdraw_cash() {
        let module_owner = @0x0;
        let user = @0xb;
        let user2 = @0xc;
        let mut scenario = test_scenario::begin(module_owner);
        {
            init(scenario.ctx());
        };
        random::create_for_testing(scenario.ctx());
        scenario.next_tx(user);
        let mut the_gram = scenario.take_shared<TheGram>();
        let random_state = scenario.take_shared<Random>();
        let mut gen = random::new_generator(&random_state,scenario.ctx());
        let rand_bytes = random::generate_bytes(&mut gen,32);
        let mut _meme_id = object::id_from_bytes(rand_bytes);
        {
            createUser(&mut the_gram, scenario.ctx());
            let title = b"Meme with cash";
            let tags = vector[string::utf8(b"cash")];
            createMeme(&random_state,scenario.ctx(), tags, b"cash_image", &mut the_gram, title);
            let meme = vector::borrow_mut(&mut the_gram.memes, 0);
            _meme_id = meme.id;
        };
        let tx = scenario.next_tx(user2);
        assert_eq(test_scenario::num_user_events(&tx), 1);
        {
            createUser(&mut the_gram, scenario.ctx());
            like(&mut the_gram,_meme_id,  scenario.ctx());
            test_scenario::return_shared(random_state)
        };
        scenario.next_tx(user);
        assert_eq(test_scenario::num_user_events(&tx), 1);
        {
            let meme = vector::borrow_mut(&mut the_gram.memes, 0);
            // let  = coin::mint_for_testing<SUI>(100,scenario.ctx());
            withdraw(meme, scenario.ctx());
            assert_eq(balance::value(&meme.cash),0);
            test_scenario::return_shared(the_gram);
        };
        let tx = scenario.end();
        assert_eq(test_scenario::num_user_events(&tx), 1)
    }
}
