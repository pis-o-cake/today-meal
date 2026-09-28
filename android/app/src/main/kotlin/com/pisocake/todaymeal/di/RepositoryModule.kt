package com.pisocake.todaymeal.di

import com.pisocake.todaymeal.data.repository.CommandRepositoryImpl
import com.pisocake.todaymeal.data.repository.InventoryRepositoryImpl
import com.pisocake.todaymeal.domain.repository.CommandRepository
import com.pisocake.todaymeal.domain.repository.InventoryRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/** 인터페이스와 구현을 잇는다. ViewModel 은 구현을 모른다. */
@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindInventoryRepository(impl: InventoryRepositoryImpl): InventoryRepository

    @Binds
    @Singleton
    abstract fun bindCommandRepository(impl: CommandRepositoryImpl): CommandRepository
}
